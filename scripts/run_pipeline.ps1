param(
  [string]$ApiKey = $env:GNEWS_API_KEY,
  [string]$OutputDir = ".\processed",
  [string]$GenerationInputJson = ".\processed\generation-input.json",
  [string]$RecordsJson = ".\records.normalized.json",
  [string]$ImageRecordsJson = ".\processed\records.with-images.json",
  [int]$Days = 7,
  [string]$ImageApiUrl = $(if ($env:IMAGE_API_URL) { $env:IMAGE_API_URL } else { "http://10.90.0.142:8088/v1/images/generations" }),
  [string]$ImageModel = $(if ($env:IMAGE_MODEL) { $env:IMAGE_MODEL } else { "gpt-image-2" }),
  [string]$ImageApiKey = $env:IMAGE_API_KEY,
  [string]$ImageSize = $(if ($env:IMAGE_SIZE) { $env:IMAGE_SIZE } else { "1792x1024" }),
  [ValidateSet("png", "webp")]
  [string]$ImageOutputFormat = $(if ($env:IMAGE_OUTPUT_FORMAT) { $env:IMAGE_OUTPUT_FORMAT } else { "webp" }),
  [int]$WebpQuality = 90,
  [string]$PythonExe = $env:PYTHON_EXE,
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

  $imageInputJson = $RecordsJson
  if ($Publish -and (Test-Path -LiteralPath $ImageRecordsJson)) {
    $imageInputJson = $ImageRecordsJson
  }

  & (Join-Path $scriptDir "generate_image_urls.ps1") `
    -InputJson $imageInputJson `
    -OutputJson $ImageRecordsJson `
    -SummaryJson (Join-Path $OutputDir "image-generation-summary.json") `
    -OutputImageDir (Join-Path $OutputDir "generated-images") `
    -ImageApiUrl $ImageApiUrl `
    -ImageModel $ImageModel `
    -ImageApiKey $ImageApiKey `
    -ImageSize $ImageSize `
    -ImageOutputFormat $ImageOutputFormat `
    -WebpQuality $WebpQuality `
    -PythonExe $PythonExe

  if ($Publish) {
    & (Join-Path $scriptDir "write_lark_records.ps1") -InputJson $ImageRecordsJson
  } else {
    & (Join-Path $scriptDir "write_lark_records.ps1") -InputJson $ImageRecordsJson -DryRun -OutputPayload (Join-Path $repoRoot "lark-batch-create.json")
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
Write-Host "  The write phase will generate image URLs from imagePrompt before building the Feishu payload."
Write-Host "  Then dry-run the Lark payload with:"
Write-Host "    .\scripts\run_pipeline.ps1 -WriteExistingRecords"
Write-Host "  Publish only after review with:"
Write-Host "    .\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish"
