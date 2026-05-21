param(
  [string]$ApiKey = $env:GNEWS_API_KEY,
  [string]$OutputDir = ".\processed",
  [string]$GenerationInputJson = ".\processed\generation-input.json",
  [string]$RecordsJson = ".\records.normalized.json",
  [int]$Days = 7,
  [switch]$Publish,
  [switch]$WriteExistingRecords,
  [switch]$IncludeBackup,
  [switch]$SkipBackup,
  [switch]$NoDelay
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

if ($WriteExistingRecords) {
  if (-not (Test-Path -LiteralPath $RecordsJson)) {
    throw "Generated records not found: $RecordsJson. Use the model to create records.normalized.json from processed\generation-input.json first."
  }

  $recordsText = Get-Content -LiteralPath $RecordsJson -Raw -Encoding UTF8
  if (-not $recordsText -or $recordsText.Trim() -eq "[]") {
    throw "Generated records file is empty: $RecordsJson"
  }

  if ($Publish) {
    & (Join-Path $scriptDir "write_lark_records.ps1") -InputJson $RecordsJson
  } else {
    & (Join-Path $scriptDir "write_lark_records.ps1") -InputJson $RecordsJson -DryRun -OutputPayload (Join-Path $repoRoot "lark-batch-create.json")
  }
  exit 0
}

if ($Publish) {
  throw "This pipeline no longer auto-generates publishable copy. First run without -Publish, let the model create records.normalized.json, then run: .\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish"
}

$fetchArgs = @{
  ApiKey = $ApiKey
  OutputDir = $OutputDir
  Days = $Days
}
if ($IncludeBackup -or -not $SkipBackup) { $fetchArgs.IncludeBackup = $true }
if ($NoDelay) { $fetchArgs.NoDelay = $true }

& (Join-Path $scriptDir "fetch-gnews.ps1") @fetchArgs
& (Join-Path $scriptDir "score-and-select.ps1") -InputJson (Join-Path $OutputDir "filtered_articles.json") -OutputJson $GenerationInputJson

Write-Host ""
Write-Host "Next step:"
Write-Host "  Use the model to rewrite processed\generation-input.json into records.normalized.json."
Write-Host "  Then dry-run the Lark payload with:"
Write-Host "    .\scripts\run_pipeline.ps1 -WriteExistingRecords"
Write-Host "  Publish only after review with:"
Write-Host "    .\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish"
