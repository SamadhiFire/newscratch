param(
  [Parameter(Mandatory = $true)]
  [string]$InputJson,

  [string]$BaseToken = "ZpWrbn0M9ajJn8s6qDycQhDWnsN",
  [string]$TableId = "tblIDJ3Nv9Q2roXL",
  [string]$LarkCli = $env:LARK_CLI,
  [string]$OutputPayload = "lark-batch-create.json",
  [switch]$DryRun
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

$allowedCategories = @(
  (U "\u79d1\u6280AI"),
  (U "\u5a31\u4e50\u4f53\u80b2"),
  (U "\u65c5\u6e38"),
  (U "\u7f8e\u98df")
)

$defaultStatus = U "\u5df2\u751f\u6210"
$defaultPublishStatus = U "\u672a\u53d1\u5e03"

if (-not (Test-Path -LiteralPath $InputJson)) {
  throw "Input JSON not found: $InputJson"
}

$records = Get-Content -LiteralPath $InputJson -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $records) {
  throw "Input JSON is empty or invalid."
}
if ($records -isnot [System.Array]) {
  $records = @($records)
}

$fields = @(
  (U "\u65b0\u95fb\u5206\u7c7b"),
  (U "\u65b0\u95fb\u6765\u6e90\u94fe\u63a5"),
  (U "\u65b0\u95fb\u6807\u9898"),
  (U "\u65b0\u95fb\u6b63\u6587"),
  (U "\u53d1\u5e03\u65e5\u671f"),
  (U "\u72b6\u6001"),
  (U "AI\u8bc4\u5206"),
  (U "AI\u8bc4\u4ef7\u5185\u5bb9"),
  (U "\u4f18\u5316\u540e\u6807\u9898"),
  (U "\u4f18\u5316\u540e\u6b63\u6587"),
  (U "\u6587\u751f\u56fe\u63d0\u793a\u8bcd"),
  (U "\u53d1\u5e03\u72b6\u6001")
)

$rows = @()

foreach ($record in $records) {
  if (-not $record.category -or $allowedCategories -notcontains [string]$record.category) {
    throw "Invalid category: $($record.category)"
  }
  if (-not $record.sourceUrl -or ([string]$record.sourceUrl -notmatch '^https?://')) {
    throw "Invalid sourceUrl for category $($record.category): $($record.sourceUrl)"
  }
  if (-not $record.generatedTitle) {
    throw "Missing generatedTitle for URL $($record.sourceUrl)"
  }
  if (-not $record.body) {
    throw "Missing body for URL $($record.sourceUrl)"
  }
  if (-not $record.imagePrompt) {
    throw "Missing imagePrompt for URL $($record.sourceUrl)"
  }

  $publishedAt = if ($record.publishedAt) { [string]$record.publishedAt } else { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
  $status = if ($record.status) { [string]$record.status } else { $defaultStatus }
  $publishStatus = if ($record.publishStatus) { [string]$record.publishStatus } else { $defaultPublishStatus }
  $sourceTitle = if ($record.sourceTitle) { [string]$record.sourceTitle } else { [string]$record.generatedTitle }
  $sourceBody = if ($record.sourceBody) { [string]$record.sourceBody } elseif ($record.sourceContent) { [string]$record.sourceContent } else { [string]$record.body }
  $score = if ($null -ne $record.score) { [int]$record.score } else { 0 }
  $evaluation = if ($record.evaluation) { [string]$record.evaluation } else { "" }

  $rows += ,@(
    [string]$record.category,
    [string]$record.sourceUrl,
    $sourceTitle,
    $sourceBody,
    $publishedAt,
    $status,
    $score,
    $evaluation,
    [string]$record.generatedTitle,
    [string]$record.body,
    [string]$record.imagePrompt,
    $publishStatus
  )
}

$payload = [ordered]@{
  fields = $fields
  rows = $rows
}

$outputPath = Resolve-OutputPath -Path $OutputPayload
$outputParent = Split-Path -Parent $outputPath
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) {
  New-Item -ItemType Directory -Path $outputParent | Out-Null
}

$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($outputPath, $json, [System.Text.UTF8Encoding]::new($false))

if ($DryRun) {
  Write-Host "Dry run. Payload written to $outputPath"
  Write-Host "Rows: $($rows.Count)"
  exit 0
}

if (-not $LarkCli -or -not (Test-Path -LiteralPath $LarkCli)) {
  $resolved = Get-Command lark-cli -ErrorAction SilentlyContinue
  if ($null -eq $resolved) {
    throw "lark-cli not found. Set LARK_CLI or pass -LarkCli with the full path."
  }
  $LarkCli = $resolved.Source
}

& $LarkCli base +record-batch-create --base-token $BaseToken --table-id $TableId --as user --json "@$outputPath"
