param(
  [string]$InputJson = ".\processed\generation-input.json",
  [string]$OutputJson = ".\records.normalized.json",
  [string]$SummaryJson = ".\processed\record-generation-summary.json",
  [string]$ApiBase = $(if ($env:TEXT_API_BASE) { $env:TEXT_API_BASE } else { "https://newapi.860812.xyz" }),
  [string]$ApiKey = $(if ($env:TEXT_API_KEY) { $env:TEXT_API_KEY } else { $env:IMAGE_API_KEY }),
  [string]$Model = $(if ($env:TEXT_MODEL) { $env:TEXT_MODEL } else { "gpt-5.4-mini" }),
  [int]$TimeoutSeconds = 180,
  [int]$MaxItems = 0,
  [int]$StartIndex = 1,
  [switch]$Resume
)

$ErrorActionPreference = "Stop"

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

function ConvertFrom-ModelJson {
  param([string]$Content)
  $clean = $Content.Trim()
  $clean = $clean -replace "^\s*```(?:json)?\s*", ""
  $clean = $clean -replace "\s*```\s*$", ""
  return ($clean | ConvertFrom-Json)
}

function Test-GeneratedRecord {
  param($Generated)

  $title = Get-Text $Generated.generatedTitle
  $body = Get-Text $Generated.body
  $prompt = Get-Text $Generated.imagePrompt

  if (-not $title) { throw "missing generatedTitle" }
  if ($title.Length -gt 90) { throw "generatedTitle is longer than 90 characters" }
  if ($title -match "(\.\.\.|\u2026)$") { throw "generatedTitle looks truncated" }
  if (-not $body) { throw "missing body" }
  if ($body.Length -lt 3500 -or $body.Length -gt 5000) {
    throw "body length must be 3500-5000 characters; got $($body.Length)"
  }
  if ($body -match "(?i)^\s*(A report from|According to the source|This story fits)\b") {
    throw "body starts like an internal summary"
  }
  if ($body -match "\[\+?\d+\s+chars\]") {
    throw "body contains a source truncation marker"
  }
  if (-not $prompt) { throw "missing imagePrompt" }
}

function New-GenerationMessages {
  param($Item, [string]$RepairNote)

  $source = [ordered]@{
    category = Get-Text $Item.category
    categoryEnglish = Get-Text $Item.categoryEnglish
    sourceTitle = Get-Text $Item.sourceTitle
    sourceDescription = Get-Text $Item.sourceDescription
    sourceBody = Get-Text $Item.sourceBody
    sourceName = Get-Text $Item.sourceName
    publishedAt = Get-Text $Item.publishedAt
    sourceUrl = Get-Text $Item.sourceUrl
    score = $Item.score
    evaluation = Get-Text $Item.evaluation
  } | ConvertTo-Json -Depth 8

  $system = @"
You are a careful English news editor for a Feishu/Lark publishing workflow.
Return exactly one valid JSON object, with no markdown and no extra prose.
Use only the provided source fields. Do not invent quotes, numbers, dates, places, company actions, legal outcomes, or claims not supported by the source.
"@

  $user = @"
Create a publishable normalized record from this source item.

Required JSON fields:
- generatedTitle: a rewritten English headline, complete, 45-90 characters, not ending with ellipsis.
- body: a formal English news article, 3500-4500 characters. It must read like a standalone article, not an internal summary.
- imagePrompt: a 16:9 professional editorial cover image prompt. It must request no text, no watermark, and no logo.
- generatedBy: exactly "model".

Writing rules:
- Preserve factual accuracy.
- If the source is short, add careful background and implications only when they are directly supported by the source category and source wording.
- Do not add unsupported quotes, statistics, named people, locations, dates, or outcomes.
- Do not include source truncation markers like [+123 chars].

Source item:
$source
"@

  if ($RepairNote) {
    $user += "`nPrevious output failed validation: $RepairNote`nRegenerate the whole JSON object and satisfy every rule."
  }

  return @(
    @{ role = "system"; content = $system },
    @{ role = "user"; content = $user }
  )
}

function Invoke-RecordGeneration {
  param($Item, [string]$RepairNote)

  $endpoint = $ApiBase.TrimEnd("/") + "/v1/chat/completions"
  $body = @{
    model = $Model
    messages = New-GenerationMessages -Item $Item -RepairNote $RepairNote
    temperature = 0.4
    max_tokens = 1600
  } | ConvertTo-Json -Depth 20

  $headers = @{
    Authorization = "Bearer $ApiKey"
    "Content-Type" = "application/json"
  }

  $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $body -TimeoutSec $TimeoutSeconds
  $content = Get-Text $response.choices[0].message.content
  if (-not $content) {
    throw "empty model response"
  }

  $generated = ConvertFrom-ModelJson -Content $content
  Test-GeneratedRecord -Generated $generated
  return $generated
}

if (-not (Test-Path -LiteralPath $InputJson)) {
  throw "Input JSON not found: $InputJson"
}
if (-not $ApiKey) {
  throw "Text API key is missing. Set TEXT_API_KEY or IMAGE_API_KEY, or pass -ApiKey."
}

$items = Get-Content -Raw -Encoding UTF8 -LiteralPath $InputJson | ConvertFrom-Json
if ($items -isnot [System.Array]) {
  $items = @($items)
}

$outputPath = Resolve-OutputPath -Path $OutputJson
$summaryPath = Resolve-OutputPath -Path $SummaryJson
Ensure-ParentDirectory -Path $outputPath
Ensure-ParentDirectory -Path $summaryPath

$existingByUrl = @{}
$records = @()
if ($Resume -and (Test-Path -LiteralPath $outputPath)) {
  $existing = Get-Content -Raw -Encoding UTF8 -LiteralPath $outputPath | ConvertFrom-Json
  foreach ($record in @($existing)) {
    $url = Get-Text $record.sourceUrl
    if ($url) {
      $existingByUrl[$url] = $record
      $records += $record
    }
  }
}

$start = [Math]::Max(1, $StartIndex)
$end = $items.Count
if ($MaxItems -gt 0) {
  $end = [Math]::Min($items.Count, $start + $MaxItems - 1)
}

$results = @()
$generatedCount = 0
$reusedCount = 0
$failedCount = 0

for ($i = $start; $i -le $end; $i++) {
  $item = $items[$i - 1]
  $sourceUrl = Get-Text $item.sourceUrl

  if ($Resume -and $existingByUrl.ContainsKey($sourceUrl)) {
    Write-Host ("[{0}/{1}] Reusing {2}" -f $i, $items.Count, $sourceUrl)
    $reusedCount++
    $results += [pscustomobject]@{ index = $i; sourceUrl = $sourceUrl; result = "reused"; error = $null }
    continue
  }

  Write-Host ("[{0}/{1}] Generating record for {2}" -f $i, $items.Count, $sourceUrl)
  $generated = $null
  $errorText = $null

  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      $repairNote = if ($attempt -gt 1) { $errorText } else { "" }
      $generated = Invoke-RecordGeneration -Item $item -RepairNote $repairNote
      break
    } catch {
      $errorText = $_.Exception.Message
      Write-Warning ("  Attempt {0} failed: {1}" -f $attempt, $errorText)
      if ($attempt -lt 3) {
        Start-Sleep -Seconds (5 * $attempt)
      }
    }
  }

  if ($generated) {
    $record = [ordered]@{
      category = $item.category
      sourceUrl = $item.sourceUrl
      sourceTitle = $item.sourceTitle
      sourceBody = if ($item.sourceBody) { $item.sourceBody } else { $item.sourceDescription }
      publishedAt = $item.publishedAt
      generatedTitle = $generated.generatedTitle
      body = $generated.body
      imagePrompt = $generated.imagePrompt
      generatedImageUrl = ""
      generatedImagePath = ""
      generatedBy = "model"
      score = $item.score
      evaluation = $item.evaluation
      status = $item.status
      publishStatus = $item.publishStatus
    }

    $records += [pscustomobject]$record
    $generatedCount++
    $results += [pscustomobject]@{ index = $i; sourceUrl = $sourceUrl; result = "generated"; error = $null }
    [System.IO.File]::WriteAllText($outputPath, (ConvertTo-Json -InputObject @($records) -Depth 12), [System.Text.UTF8Encoding]::new($false))
  } else {
    $failedCount++
    $results += [pscustomobject]@{ index = $i; sourceUrl = $sourceUrl; result = "failed"; error = $errorText }
  }
}

$summary = [ordered]@{
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  apiBase = $ApiBase
  model = $Model
  input = $InputJson
  output = $OutputJson
  totalInput = $items.Count
  requestedStartIndex = $start
  requestedEndIndex = $end
  outputRecords = @($records).Count
  generated = $generatedCount
  reused = $reusedCount
  failed = $failedCount
  results = $results
}

[System.IO.File]::WriteAllText($summaryPath, (ConvertTo-Json -InputObject $summary -Depth 12), [System.Text.UTF8Encoding]::new($false))

Write-Host "Saved generated records to: $OutputJson"
Write-Host "Saved generation summary to: $SummaryJson"
Write-Host ("Record generation summary: output={0}, generated={1}, reused={2}, failed={3}" -f @($records).Count, $generatedCount, $reusedCount, $failedCount)
