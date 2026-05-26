param(
  [string]$InputJson = ".\processed\generation-input.json",
  [string[]]$RecordJsons = @(
    ".\records.normalized.json",
    ".\processed\records.chunk-a.json",
    ".\processed\records.chunk-b.json",
    ".\processed\records.chunk-c.json",
    ".\processed\records.chunk-d.json",
    ".\processed\records.missing.retry.json"
  ),
  [string[]]$SummaryJsons = @(
    ".\processed\record-generation-chunk-a.summary.json",
    ".\processed\record-generation-chunk-b.summary.json",
    ".\processed\record-generation-chunk-c.summary.json",
    ".\processed\record-generation-chunk-d.summary.json",
    ".\processed\record-generation-retry-missing.summary.json"
  ),
  [string]$OutputJson = ".\records.normalized.json",
  [string]$MissingJson = ".\processed\record-generation-missing.json",
  [string]$SummaryJson = ".\processed\record-generation-merged-summary.json"
)

$ErrorActionPreference = "Stop"

function Resolve-OutputPath {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
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

if (-not (Test-Path -LiteralPath $InputJson)) {
  throw "Input JSON not found: $InputJson"
}

$items = Get-Content -Raw -Encoding UTF8 -LiteralPath $InputJson | ConvertFrom-Json
$recordsByUrl = @{}

foreach ($path in $RecordJsons) {
  if (-not (Test-Path -LiteralPath $path)) { continue }
  $records = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
  foreach ($record in @($records)) {
    $url = Get-Text $record.sourceUrl
    if ($url -and -not $recordsByUrl.ContainsKey($url)) {
      $recordsByUrl[$url] = $record
    }
  }
}

$merged = @()
$missing = @()
foreach ($item in @($items)) {
  $url = Get-Text $item.sourceUrl
  if ($recordsByUrl.ContainsKey($url)) {
    $merged += $recordsByUrl[$url]
  } else {
    $missing += $item
  }
}

$failedResults = @()
foreach ($path in $SummaryJsons) {
  if (-not (Test-Path -LiteralPath $path)) { continue }
  $summary = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
  $failedResults += @($summary.results | Where-Object { $_.result -eq "failed" })
}

$outputPath = Resolve-OutputPath -Path $OutputJson
$missingPath = Resolve-OutputPath -Path $MissingJson
$summaryPath = Resolve-OutputPath -Path $SummaryJson
Ensure-ParentDirectory -Path $outputPath
Ensure-ParentDirectory -Path $missingPath
Ensure-ParentDirectory -Path $summaryPath

[System.IO.File]::WriteAllText($outputPath, (ConvertTo-Json -InputObject @($merged) -Depth 12), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($missingPath, (ConvertTo-Json -InputObject @($missing) -Depth 12), [System.Text.UTF8Encoding]::new($false))

$summaryOut = [ordered]@{
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  totalInput = @($items).Count
  mergedRecords = @($merged).Count
  missingRecords = @($missing).Count
  failedResults = @($failedResults).Count
  outputJson = $OutputJson
  missingJson = $MissingJson
  failed = $failedResults
}
[System.IO.File]::WriteAllText($summaryPath, (ConvertTo-Json -InputObject $summaryOut -Depth 12), [System.Text.UTF8Encoding]::new($false))

Write-Host "Merged records: $(@($merged).Count)"
Write-Host "Missing records: $(@($missing).Count)"
Write-Host "Saved merged records to: $OutputJson"
Write-Host "Saved missing input items to: $MissingJson"
