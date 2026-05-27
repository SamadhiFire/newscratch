param(
  [string]$InputJson = ".\records.normalized.json",
  [string]$Date = (Get-Date -Format "yyyy-MM-dd"),
  [string]$OutputDir = ".\dist",
  [string]$ImageApiUrl = $env:IMAGE_API_URL,
  [string]$ImageApiKey = $env:IMAGE_API_KEY,
  [string]$ImageModel = $(if ($env:IMAGE_MODEL) { $env:IMAGE_MODEL } else { "gpt-image-2" }),
  [string]$ImageSize = $(if ($env:IMAGE_SIZE) { $env:IMAGE_SIZE } else { "1152x576" }),
  [string]$PythonExe = $env:PYTHON_EXE,
  [int]$Workers = 3,
  [int]$MaxImageAttempts = 3,
  [switch]$Resume,
  [switch]$SkipImageGeneration,
  [switch]$NoZip
)

$ErrorActionPreference = "Stop"

function Resolve-OutputPath {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path (Get-Location) $Path)
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Get-Text {
  param($Value)
  if ($null -eq $Value) { return "" }
  return [string]$Value
}

function ConvertTo-Slug {
  param(
    [string]$Text,
    [int]$MaxLength = 72
  )

  $value = (Get-Text $Text).ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  $chars = New-Object System.Text.StringBuilder
  foreach ($char in $value.ToCharArray()) {
    $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
    if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$chars.Append($char)
    }
  }

  $slug = $chars.ToString().Normalize([Text.NormalizationForm]::FormC)
  $slug = [regex]::Replace($slug, "[^a-z0-9]+", "-").Trim("-")
  if (-not $slug) { $slug = "post" }
  if ($slug.Length -gt $MaxLength) {
    $slug = $slug.Substring(0, $MaxLength).Trim("-")
  }
  return $slug
}

function ConvertTo-ArticleMarkdown {
  param($Record, [string]$Title)

  $markdown = Get-Text $Record.articleMarkdown
  if (-not $markdown) { $markdown = Get-Text $Record.bodyMarkdown }
  if ($markdown) { return $markdown.Trim() + "`n" }

  $body = Get-Text $Record.body
  if (-not $body) { $body = Get-Text $Record.content }
  if (-not $body) { throw "Missing article body for: $Title" }

  $body = [regex]::Replace($body.Trim(), "(`r`n|`n|`r){3,}", "`n`n")
  if ($body -notmatch "^#\s") {
    return "# $Title`n`n$body`n"
  }
  return "$body`n"
}

function Resolve-PythonExecutable {
  param([string]$ExplicitPath)

  if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath -ErrorAction SilentlyContinue)) {
    return (Resolve-Path -LiteralPath $ExplicitPath).Path
  }

  foreach ($commandName in @("python3", "python", "py")) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
  }

  return $null
}

function Write-Utf8Json {
  param($Value, [string]$Path, [int]$Depth = 12)
  [System.IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth $Depth), [System.Text.UTF8Encoding]::new($false))
}

function Test-WebPFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 12) { return $false }
  $riff = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
  $webp = [System.Text.Encoding]::ASCII.GetString($bytes, 8, 4)
  return ($riff -eq "RIFF" -and $webp -eq "WEBP")
}

function New-ZipWithSingleTopDirectory {
  param(
    [string]$SourceDirectory,
    [string]$TopDirectoryName,
    [string]$ZipPath
  )

  if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
  }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    $root = (Resolve-Path -LiteralPath $SourceDirectory).Path.TrimEnd([char[]]@("\", "/"))
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
      $relative = $file.FullName.Substring($root.Length).TrimStart([char[]]@("\", "/")) -replace "\\", "/"
      $entryName = "$TopDirectoryName/$relative"
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
  } finally {
    $zip.Dispose()
  }
}

function Test-SingleTopDirectoryZip {
  param([string]$ZipPath, [string]$ExpectedTopDirectory)

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $tops = @{}
    foreach ($entry in $zip.Entries) {
      if (-not $entry.FullName) { continue }
      $top = ($entry.FullName -split "/")[0]
      if ($top) { $tops[$top] = $true }
    }
    return ($tops.Count -eq 1 -and $tops.ContainsKey($ExpectedTopDirectory))
  } finally {
    $zip.Dispose()
  }
}

function Invoke-ImageWorkers {
  param(
    [object[]]$Tasks,
    [string]$Url,
    [string]$Key,
    [string]$Model,
    [string]$Size,
    [string]$PythonPath,
    [int]$WorkerCount,
    [int]$Attempts
  )

  if ($Tasks.Count -eq 0) { return @() }
  if (-not $Url -or $Url -notmatch "^https?://") { throw "IMAGE_API_URL is required for image generation." }
  if (-not $Key) { throw "IMAGE_API_KEY is required for image generation." }
  if (-not $PythonPath) { throw "Python with Pillow WebP support is required. Set PYTHON_EXE." }

  $WorkerCount = [Math]::Max(1, [Math]::Min($WorkerCount, $Tasks.Count))
  $chunks = @()
  for ($i = 0; $i -lt $WorkerCount; $i++) { $chunks += ,@() }
  for ($i = 0; $i -lt $Tasks.Count; $i++) {
    $chunks[$i % $WorkerCount] += $Tasks[$i]
  }

  $scriptBlock = {
    param($ChunkTasks, $ImageApiUrl, $ImageApiKey, $ImageModel, $ImageSize, $PythonExe, $MaxAttempts)

    function Get-Text {
      param($Value)
      if ($null -eq $Value) { return "" }
      return [string]$Value
    }

    function Convert-ImageToWebP {
      param([string]$InputPath, [string]$OutputPath, [string]$PythonPath)

      $script = @"
from PIL import Image, features
import sys

src, dst = sys.argv[1], sys.argv[2]
if not features.check('webp'):
    raise RuntimeError('Pillow was built without WebP support')
img = Image.open(src)
img.save(dst, format='WEBP', quality=90, method=6)
"@

      $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("spaceplayax-webp-{0}.py" -f ([guid]::NewGuid().ToString("N")))
      [System.IO.File]::WriteAllText($tempScript, $script, [System.Text.UTF8Encoding]::new($false))
      try {
        $output = & $PythonPath $tempScript $InputPath $OutputPath 2>&1
        if ($LASTEXITCODE -ne 0) {
          throw (($output | Out-String).Trim())
        }
      } finally {
        Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
      }
    }

    function Invoke-OneImage {
      param($Task)

      $headers = @{
        "Content-Type" = "application/json"
        Authorization = "Bearer $ImageApiKey"
      }
      $body = @{
        model = $ImageModel
        prompt = $Task.imagePrompt
        size = $ImageSize
      } | ConvertTo-Json -Depth 6

      $response = Invoke-RestMethod -Uri $ImageApiUrl -Method Post -Headers $headers -Body $body -TimeoutSec 300
      if (-not $response.data -or $response.data.Count -eq 0) {
        throw "Image API response did not include data[0]."
      }

      $first = $response.data[0]
      $sourcePath = Join-Path $Task.imagesDir "cover-source"
      if ($first.b64_json) {
        $sourcePath = "$sourcePath.png"
        [System.IO.File]::WriteAllBytes($sourcePath, [Convert]::FromBase64String((Get-Text $first.b64_json)))
      } elseif ($first.url) {
        $sourcePath = "$sourcePath.download"
        Invoke-WebRequest -Uri (Get-Text $first.url) -OutFile $sourcePath -TimeoutSec 300
      } else {
        throw "Image API returned neither b64_json nor url."
      }

      Convert-ImageToWebP -InputPath $sourcePath -OutputPath $Task.coverPath -PythonPath $PythonExe
      Remove-Item -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue
    }

    $results = @()
    foreach ($task in @($ChunkTasks)) {
      $ok = $false
      $errorText = $null
      for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
          Invoke-OneImage -Task $task
          $ok = $true
          break
        } catch {
          $errorText = $_.Exception.Message
          Start-Sleep -Seconds ([Math]::Min(30, 5 * $attempt))
        }
      }

      $results += [pscustomobject]@{
        slug = $task.slug
        sourceUrl = $task.sourceUrl
        coverPath = $task.coverPath
        ok = $ok
        error = $errorText
      }
    }
    return $results
  }

  $jobs = @()
  foreach ($chunk in $chunks) {
    if ($chunk.Count -eq 0) { continue }
    $jobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList (,$chunk), $Url, $Key, $Model, $Size, $PythonPath, $Attempts
  }

  $allResults = @()
  try {
    foreach ($job in $jobs) {
      Wait-Job -Job $job | Out-Null
      $allResults += Receive-Job -Job $job
    }
  } finally {
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
  }

  return $allResults
}

if ($Date -notmatch "^\d{4}-\d{2}-\d{2}$") {
  throw "Date must use yyyy-MM-dd format."
}
if ($Workers -lt 1) { throw "Workers must be at least 1." }
if (-not (Test-Path -LiteralPath $InputJson)) {
  throw "Input JSON not found: $InputJson"
}

$outputRoot = Resolve-OutputPath -Path $OutputDir
Ensure-Directory -Path $outputRoot

$batchName = "spaceplayax-content-batch-$Date"
$batchDir = Join-Path $outputRoot $batchName
$buildSummaryPath = Join-Path $outputRoot "$batchName-build-summary.json"
$postsDir = Join-Path $batchDir "posts"
Ensure-Directory -Path $batchDir
Ensure-Directory -Path $postsDir

$legacyBuildSummary = Join-Path $batchDir "build-summary.json"
if (Test-Path -LiteralPath $legacyBuildSummary) {
  Remove-Item -LiteralPath $legacyBuildSummary -Force
}

$records = Get-Content -Raw -Encoding UTF8 -LiteralPath $InputJson | ConvertFrom-Json
if ($records -isnot [System.Array]) { $records = @($records) }
if ($records.Count -eq 0) { throw "Input JSON contains no articles." }

$seenSlugs = @{}
$postManifests = @()
$imageTasks = @()

for ($i = 0; $i -lt $records.Count; $i++) {
  $record = $records[$i]
  $title = Get-Text $record.generatedTitle
  if (-not $title) { $title = Get-Text $record.title }
  if (-not $title) { throw "Missing title for article index $($i + 1)." }

  $baseSlug = Get-Text $record.slug
  if (-not $baseSlug) { $baseSlug = ConvertTo-Slug -Text $title }

  $slug = $baseSlug
  $suffix = 2
  while ($seenSlugs.ContainsKey($slug)) {
    $slug = "$baseSlug-$suffix"
    $suffix++
  }
  $seenSlugs[$slug] = $true

  $postId = "$Date-$slug"
  $postDir = Join-Path $postsDir $postId
  $imagesDir = Join-Path $postDir "images"
  Ensure-Directory -Path $postDir
  Ensure-Directory -Path $imagesDir

  $articlePath = Join-Path $postDir "article.md"
  $manifestPath = Join-Path $postDir "manifest.json"
  $coverPath = Join-Path $imagesDir "cover.webp"

  $markdown = ConvertTo-ArticleMarkdown -Record $record -Title $title
  [System.IO.File]::WriteAllText($articlePath, $markdown, [System.Text.UTF8Encoding]::new($false))

  $imagePrompt = Get-Text $record.imagePrompt
  if (-not $imagePrompt) {
    $imagePrompt = "Professional editorial cover image for an article titled '$title', cinematic lighting, no text, no watermark, no logo."
  }

  $manifest = [ordered]@{
    id = $postId
    slug = $slug
    title = $title
    date = $Date
    category = Get-Text $record.category
    sourceUrl = Get-Text $record.sourceUrl
    sourceTitle = Get-Text $record.sourceTitle
    sourceName = Get-Text $record.sourceName
    publishedAt = Get-Text $record.publishedAt
    article = "article.md"
    coverImage = "images/cover.webp"
    imagePrompt = $imagePrompt
  }
  Write-Utf8Json -Value $manifest -Path $manifestPath
  $postManifests += [pscustomobject]$manifest

  if (-not $SkipImageGeneration) {
    if ($Resume -and (Test-WebPFile -Path $coverPath)) {
      continue
    }
    $imageTasks += [pscustomobject]@{
      slug = $slug
      sourceUrl = Get-Text $record.sourceUrl
      imagePrompt = $imagePrompt
      imagesDir = $imagesDir
      coverPath = $coverPath
    }
  }
}

$imageResults = @()
if (-not $SkipImageGeneration) {
  $pythonPath = Resolve-PythonExecutable -ExplicitPath $PythonExe
  $imageResults = Invoke-ImageWorkers `
    -Tasks $imageTasks `
    -Url $ImageApiUrl `
    -Key $ImageApiKey `
    -Model $ImageModel `
    -Size $ImageSize `
    -PythonPath $pythonPath `
    -WorkerCount $Workers `
    -Attempts $MaxImageAttempts
}

$batchManifest = [ordered]@{
  batchName = $batchName
  date = $Date
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  articleCount = @($postManifests).Count
  posts = @($postManifests | ForEach-Object {
      [ordered]@{
        id = $_.id
        slug = $_.slug
        title = $_.title
        date = $_.date
        category = $_.category
        manifest = "posts/$($_.id)/manifest.json"
        article = "posts/$($_.id)/article.md"
        coverImage = "posts/$($_.id)/images/cover.webp"
      }
    })
}
Write-Utf8Json -Value $batchManifest -Path (Join-Path $batchDir "batch-manifest.json") -Depth 14

$missing = @()
foreach ($manifest in $postManifests) {
  $postDir = Join-Path $postsDir $manifest.id
  $cover = Join-Path (Join-Path $postDir "images") "cover.webp"
  $checks = @(
    (Join-Path $postDir "manifest.json"),
    (Join-Path $postDir "article.md"),
    $cover
  )
  foreach ($path in $checks) {
    if (-not (Test-Path -LiteralPath $path)) {
      $missing += $path
    }
  }
  if ((Test-Path -LiteralPath $cover) -and -not (Test-WebPFile -Path $cover)) {
    $missing += "$cover is not a valid WebP file"
  }
}

$summary = [ordered]@{
  batchName = $batchName
  batchDir = $batchDir
  zipPath = ""
  inputJson = $InputJson
  totalArticles = $records.Count
  imageTasks = @($imageTasks).Count
  imageGenerated = @($imageResults | Where-Object { $_.ok }).Count
  imageFailed = @($imageResults | Where-Object { -not $_.ok }).Count
  missing = $missing
  imageResults = $imageResults
}

if ($missing.Count -gt 0) {
  Write-Utf8Json -Value $summary -Path $buildSummaryPath -Depth 14
  throw "Batch is incomplete. Missing or invalid files: $($missing.Count). See $buildSummaryPath"
}

if (-not $NoZip) {
  $zipPath = Join-Path $outputRoot "$batchName.zip"
  New-ZipWithSingleTopDirectory -SourceDirectory $batchDir -TopDirectoryName $batchName -ZipPath $zipPath
  if (-not (Test-SingleTopDirectoryZip -ZipPath $zipPath -ExpectedTopDirectory $batchName)) {
    throw "Zip validation failed: archive must contain exactly one top-level directory named $batchName."
  }
  $summary.zipPath = $zipPath
}

Write-Utf8Json -Value $summary -Path $buildSummaryPath -Depth 14

Write-Host "Batch directory: $batchDir"
if ($summary.zipPath) { Write-Host "Batch zip: $($summary.zipPath)" }
Write-Host ("Articles: {0}; images generated: {1}; image failures: {2}" -f $records.Count, $summary.imageGenerated, $summary.imageFailed)
