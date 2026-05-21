param(
  [string]$ApiKey = $env:GNEWS_API_KEY,
  [string]$OutputDir = ".\processed",
  [string]$RecordsJson = ".\records.normalized.json",
  [int]$Days = 7,
  [switch]$Publish,
  [switch]$IncludeBackup,
  [switch]$NoDelay
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

$fetchArgs = @{
  ApiKey = $ApiKey
  OutputDir = $OutputDir
  Days = $Days
}
if ($IncludeBackup) { $fetchArgs.IncludeBackup = $true }
if ($NoDelay) { $fetchArgs.NoDelay = $true }

& (Join-Path $scriptDir "fetch-gnews.ps1") @fetchArgs
& (Join-Path $scriptDir "score-and-generate.ps1") -InputJson (Join-Path $OutputDir "filtered_articles.json") -OutputJson $RecordsJson

if ($Publish) {
  & (Join-Path $scriptDir "write_lark_records.ps1") -InputJson $RecordsJson
} else {
  & (Join-Path $scriptDir "write_lark_records.ps1") -InputJson $RecordsJson -DryRun -OutputPayload (Join-Path $repoRoot "lark-batch-create.json")
}
