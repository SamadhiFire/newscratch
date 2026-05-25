param(
  [Parameter(Mandatory = $true)]
  [string]$InputJson,

  [string]$OutputJson = ".\processed\records.with-images.json",
  [string]$SummaryJson = ".\processed\image-generation-summary.json",
  [string]$OutputImageDir = ".\processed\generated-images",
  [string]$ImageApiUrl = $env:IMAGE_API_URL,
  [string]$ImageModel = $(if ($env:IMAGE_MODEL) { $env:IMAGE_MODEL } else { "gpt-image-2" }),
  [string]$ImageApiKey = $env:IMAGE_API_KEY,
  [string]$ImageSize = $(if ($env:IMAGE_SIZE) { $env:IMAGE_SIZE } else { "1152x576" }),
  [ValidateSet("png", "webp")]
  [string]$ImageOutputFormat = $(if ($env:IMAGE_OUTPUT_FORMAT) { $env:IMAGE_OUTPUT_FORMAT } else { "webp" }),
  [int]$WebpQuality = 90,
  [int]$TimeoutSeconds = 120,
  [string]$PythonExe = $env:PYTHON_EXE
)

$ErrorActionPreference = "Stop"

function U {
  param([Parameter(Mandatory = $true)][string]$Text)
  return [System.Text.RegularExpressions.Regex]::Unescape($Text)
}

function Resolve-OutputPath {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path (Get-Location) $Path)
}

function Ensure-ParentDirectory {
  param([string]$Path)
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
  }
}

function Get-Text {
  param($Value)
  if ($null -eq $Value) { return "" }
  return [string]$Value
}

function Test-HttpUrl {
  param([string]$Value)
  return $Value -match "^https?://"
}

function Get-StableImageBaseName {
  param(
    [int]$Index,
    [string]$SourceUrl
  )

  $seed = if ($SourceUrl) { $SourceUrl } else { "record-$Index" }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($seed)
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hashBytes = $sha256.ComputeHash($bytes)
  } finally {
    $sha256.Dispose()
  }

  $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant().Substring(0, 16)
  return ("image-{0:D3}-{1}" -f $Index, $hash)
}

function Resolve-PythonExecutable {
  param([string]$ExplicitPath)

  $candidates = @()
  if ($ExplicitPath) { $candidates += $ExplicitPath }
  $candidates += @(
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
  ) | Where-Object { $_ }

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue)) {
      return $candidate
    }
  }

  $commands = @("python", "py")
  foreach ($commandName in $commands) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($command) {
      return $command.Source
    }
  }

  return $null
}

function Invoke-ImageGeneration {
  param(
    [string]$Prompt,
    [string]$Url,
    [string]$Model,
    [string]$ApiKey,
    [string]$Size,
    [int]$Timeout
  )

  $headers = @{
    "Content-Type" = "application/json"
  }
  if ($ApiKey) {
    $headers["Authorization"] = "Bearer $ApiKey"
  }

  $body = @{
    model = $Model
    prompt = $Prompt
    size = $Size
  } | ConvertTo-Json -Depth 5

  try {
    $response = Invoke-RestMethod -Uri $Url -Method Post -Headers $headers -Body $body -TimeoutSec $Timeout
  } catch {
    return [pscustomobject]@{
      ok = $false
      url = $null
      b64 = $null
      error = $_.Exception.Message
    }
  }

  $imageUrl = $null
  $imageB64 = $null
  if ($response -and $response.data -and $response.data.Count -gt 0) {
    $imageUrl = Get-Text $response.data[0].url
    $imageB64 = Get-Text $response.data[0].b64_json
  }

  if (-not (Test-HttpUrl -Value $imageUrl) -and -not $imageB64) {
    return [pscustomobject]@{
      ok = $false
      url = $null
      b64 = $null
      error = "Image API response did not contain data[0].url or data[0].b64_json"
    }
  }

  return [pscustomobject]@{
    ok = $true
    url = $imageUrl
    b64 = $imageB64
    error = $null
  }
}

function Convert-PngToWebp {
  param(
    [string]$PythonPath,
    [string]$InputPath,
    [string]$OutputPath,
    [int]$Quality
  )

  $script = @"
from PIL import Image, features
import sys

src, dst, quality = sys.argv[1], sys.argv[2], int(sys.argv[3])
if not features.check('webp'):
    raise RuntimeError('Pillow was built without WebP support')

img = Image.open(src)
img.save(dst, format='WEBP', quality=quality, method=6)
print(dst)
"@

  $tempScript = Join-Path $env:TEMP ("convert-webp-{0}.py" -f ([guid]::NewGuid().ToString("N")))
  [System.IO.File]::WriteAllText($tempScript, $script, [System.Text.UTF8Encoding]::new($false))
  try {
    $output = & $PythonPath $tempScript $InputPath $OutputPath $Quality 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw (($output | Out-String).Trim())
    }
  } finally {
    Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-Path -LiteralPath $InputJson)) {
  throw "Input JSON not found: $InputJson"
}

if (-not (Test-HttpUrl -Value $ImageApiUrl)) {
  throw "Image API URL is required. Set IMAGE_API_URL or pass -ImageApiUrl with an http/https endpoint."
}

$records = Get-Content -LiteralPath $InputJson -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $records) {
  throw "Input JSON is empty or invalid."
}
if ($records -isnot [System.Array]) {
  $records = @($records)
}

$outputPath = Resolve-OutputPath -Path $OutputJson
$summaryPath = Resolve-OutputPath -Path $SummaryJson
$outputImageDirPath = Resolve-OutputPath -Path $OutputImageDir
Ensure-ParentDirectory -Path $outputPath
Ensure-ParentDirectory -Path $summaryPath
if (-not (Test-Path -LiteralPath $outputImageDirPath)) {
  New-Item -ItemType Directory -Path $outputImageDirPath | Out-Null
}

$pythonPath = $null
if ($ImageOutputFormat -eq "webp") {
  $pythonPath = Resolve-PythonExecutable -ExplicitPath $PythonExe
  if (-not $pythonPath) {
    throw "WebP output requested, but no usable Python interpreter was found. Set PYTHON_EXE or install Python with Pillow WebP support."
  }
}

$outputRecords = @()
$results = @()
$generatedCount = 0
$reusedCount = 0
$failedCount = 0

for ($i = 0; $i -lt $records.Count; $i++) {
  $record = $records[$i]
  $prompt = Get-Text $record.imagePrompt
  $existingUrl = Get-Text $record.generatedImageUrl
  $existingPath = Get-Text $record.generatedImagePath
  $status = Get-Text $record.status

  $normalizedStatus = if ($status) { $status } else { (U "\u5df2\u751f\u6210") }
  $generatedImageUrl = $existingUrl
  $generatedImagePath = $existingPath
  $imageError = $null
  $resultType = "generated"

  if (Test-HttpUrl -Value $existingUrl) {
    $reusedCount++
    $resultType = "reused"
  } elseif ($generatedImagePath -and (Test-Path -LiteralPath $generatedImagePath)) {
    $reusedCount++
    $resultType = "reused"
  } else {
    if (-not $prompt) {
      $generatedImageUrl = ""
      $generatedImagePath = ""
      $imageError = "Missing imagePrompt"
      $normalizedStatus = U "\u5931\u8d25"
      $failedCount++
      $resultType = "failed"
    } else {
      Write-Host ("[{0}/{1}] Generating image for {2}" -f ($i + 1), $records.Count, (Get-Text $record.sourceUrl))
      $imageResult = Invoke-ImageGeneration -Prompt $prompt -Url $ImageApiUrl -Model $ImageModel -ApiKey $ImageApiKey -Size $ImageSize -Timeout $TimeoutSeconds
      if ($imageResult.ok) {
        $generatedImageUrl = if ($imageResult.url) { $imageResult.url } else { "" }

        if ($imageResult.b64) {
          $baseName = Get-StableImageBaseName -Index ($i + 1) -SourceUrl (Get-Text $record.sourceUrl)
          $pngPath = Join-Path $outputImageDirPath ("{0}.png" -f $baseName)
          try {
            [System.IO.File]::WriteAllBytes($pngPath, [Convert]::FromBase64String($imageResult.b64))
            if ($ImageOutputFormat -eq "webp") {
              $webpPath = Join-Path $outputImageDirPath ("{0}.webp" -f $baseName)
              Convert-PngToWebp -PythonPath $pythonPath -InputPath $pngPath -OutputPath $webpPath -Quality $WebpQuality
              $generatedImagePath = $webpPath
            } else {
              $generatedImagePath = $pngPath
            }
          } catch {
            $generatedImageUrl = ""
            $generatedImagePath = ""
            $imageError = "Failed to materialize generated image: $($_.Exception.Message)"
            $normalizedStatus = U "\u5931\u8d25"
            $failedCount++
            $resultType = "failed"
          }
        } elseif ($generatedImageUrl) {
          $generatedImagePath = ""
        } else {
          $generatedImageUrl = ""
          $generatedImagePath = ""
          $imageError = "Image API returned neither reusable URL nor b64 payload."
          $normalizedStatus = U "\u5931\u8d25"
          $failedCount++
          $resultType = "failed"
        }

        if ($resultType -ne "failed") {
          $generatedCount++
        }
      } else {
        $generatedImageUrl = ""
        $generatedImagePath = ""
        $imageError = $imageResult.error
        $normalizedStatus = U "\u5931\u8d25"
        $failedCount++
        $resultType = "failed"
      }
    }
  }

  $outputRecords += [pscustomobject]@{
    category = $record.category
    sourceUrl = $record.sourceUrl
    sourceTitle = $record.sourceTitle
    sourceBody = if ($record.sourceBody) { $record.sourceBody } elseif ($record.sourceContent) { $record.sourceContent } else { $null }
    publishedAt = $record.publishedAt
    generatedTitle = $record.generatedTitle
    body = $record.body
    imagePrompt = $record.imagePrompt
    generatedImageUrl = $generatedImageUrl
    generatedImagePath = $generatedImagePath
    generatedBy = $record.generatedBy
    score = $record.score
    evaluation = $record.evaluation
    status = $normalizedStatus
    publishStatus = $record.publishStatus
  }

  $results += [pscustomobject]@{
    sourceUrl = $record.sourceUrl
    result = $resultType
    generatedImageUrl = $generatedImageUrl
    generatedImagePath = $generatedImagePath
    error = $imageError
  }
}

$summary = [ordered]@{
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  imageApiUrl = $ImageApiUrl
  imageModel = $ImageModel
  imageSize = $ImageSize
  imageOutputFormat = $ImageOutputFormat
  total = $records.Count
  generated = $generatedCount
  reused = $reusedCount
  failed = $failedCount
  results = $results
}

[System.IO.File]::WriteAllText($outputPath, (ConvertTo-Json -InputObject @($outputRecords) -Depth 12), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($summaryPath, (ConvertTo-Json -InputObject $summary -Depth 12), [System.Text.UTF8Encoding]::new($false))

Write-Host "Saved image-enriched records to: $OutputJson"
Write-Host "Saved image generation summary to: $SummaryJson"
Write-Host ("Image generation summary: total={0}, generated={1}, reused={2}, failed={3}" -f $records.Count, $generatedCount, $reusedCount, $failedCount)
