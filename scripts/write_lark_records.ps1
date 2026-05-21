param(
  [Parameter(Mandatory = $true)]
  [string]$InputJson,

  [string]$BaseToken = "ZpWrbn0M9ajJn8s6qDycQhDWnsN",
  [string]$TableId = "tblIDJ3Nv9Q2roXL",
  [string]$LarkCli = "C:\Users\AS\.workbuddy\binaries\node\versions\22.12.0\lark-cli.cmd",
  [string]$OutputPayload = "lark-batch-create.json",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$allowedCategories = @("科技AI", "娱乐体育", "旅游", "美食")

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
  "新闻分类",
  "新闻来源链接",
  "新闻标题",
  "新闻正文",
  "发布日期",
  "状态",
  "AI评分",
  "AI评价内容",
  "优化后标题",
  "优化后正文",
  "文生图提示词",
  "发布状态"
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
  $status = if ($record.status) { [string]$record.status } else { "已生成" }
  $publishStatus = if ($record.publishStatus) { [string]$record.publishStatus } else { "未发布" }
  $sourceTitle = if ($record.sourceTitle) { [string]$record.sourceTitle } else { [string]$record.generatedTitle }
  $score = if ($null -ne $record.score) { [int]$record.score } else { 0 }
  $evaluation = if ($record.evaluation) { [string]$record.evaluation } else { "" }

  $rows += ,@(
    [string]$record.category,
    [string]$record.sourceUrl,
    $sourceTitle,
    [string]$record.body,
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

$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 8))
[System.IO.File]::WriteAllText((Resolve-Path $OutputPayload), ([System.Text.Encoding]::UTF8.GetString($jsonBytes)), [System.Text.UTF8Encoding]::new($false))

if ($DryRun) {
  Write-Host "Dry run. Payload written to $OutputPayload"
  Write-Host "Rows: $($rows.Count)"
  exit 0
}

if (-not (Test-Path -LiteralPath $LarkCli)) {
  $resolved = Get-Command lark-cli -ErrorAction SilentlyContinue
  if ($null -eq $resolved) {
    throw "lark-cli not found. Set -LarkCli to the full path."
  }
  $LarkCli = $resolved.Source
}

& $LarkCli base +record-batch-create --base-token $BaseToken --table-id $TableId --as user --json "@$OutputPayload"

