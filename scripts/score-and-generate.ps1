param(
  [string]$InputJson = ".\processed\filtered_articles.json",
  [string]$OutputJson = ".\processed\generation-input.json",
  [string]$SummaryJson = ".\processed\score-summary.json",
  [int]$TargetPerCategory = 25
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Warning "score-and-generate.ps1 is deprecated. It no longer creates titles or bodies. Use score-and-select.ps1, then let the model generate records.normalized.json."

& (Join-Path $scriptDir "score-and-select.ps1") `
  -InputJson $InputJson `
  -OutputJson $OutputJson `
  -SummaryJson $SummaryJson `
  -TargetPerCategory $TargetPerCategory
