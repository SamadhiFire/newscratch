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

function Get-RelativeCliPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $resolved = Resolve-Path -LiteralPath $Path
  $relative = Resolve-Path -LiteralPath $resolved.Path -Relative
  $relative = $relative -replace "\\", "/"
  if (-not $relative.StartsWith("./") -and -not $relative.StartsWith("../")) {
    $relative = "./$relative"
  }
  return $relative
}

function Resolve-ExistingCommandPath {
  param($CommandInfo)

  if ($null -eq $CommandInfo) { return $null }

  $candidates = @(
    $CommandInfo.Path,
    $CommandInfo.Source,
    $CommandInfo.Definition
  ) | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    if ($candidate -notmatch '[\r\n]' -and (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue)) {
      return $candidate
    }
  }

  foreach ($candidate in $candidates) {
    if ($candidate -notmatch '[\r\n]') {
      return $candidate
    }
  }

  return $null
}

function Invoke-LarkCli {
  param(
    [string]$LarkCliPath,
    [string[]]$Arguments
  )

  $savedNodeOptions = $env:NODE_OPTIONS
  $env:NODE_OPTIONS = ""
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & $LarkCliPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
    if ($null -ne $savedNodeOptions) { $env:NODE_OPTIONS = $savedNodeOptions } else { Remove-Item Env:\NODE_OPTIONS -ErrorAction SilentlyContinue }
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Text = ($output | Out-String).Trim()
  }
}

$allowedCategories = @(
  (U "\u79d1\u6280AI"),
  (U "\u5a31\u4e50\u4f53\u80b2"),
  (U "\u65c5\u6e38"),
  (U "\u7f8e\u98df"),
  (U "\u97f3\u4e50"),
  (U "\u751f\u6d3b")
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
  (U "\u751f\u6210\u56fe\u7247"),
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

  if (-not $record.generatedBy -or ([string]$record.generatedBy).ToLowerInvariant() -ne "model") {
    throw "Missing generatedBy=`"model`" for URL $($record.sourceUrl). Final title/body/imagePrompt must be created by the model, not by a script template."
  }

  $generatedImageUrl = if ($record.generatedImageUrl) { [string]$record.generatedImageUrl } else { "" }
  $generatedImagePath = if ($record.generatedImagePath) { [string]$record.generatedImagePath } else { "" }
  if ($generatedImageUrl -and $generatedImageUrl -notmatch '^https?://') {
    throw "Invalid generatedImageUrl for URL $($record.sourceUrl): $generatedImageUrl"
  }
  $hasGeneratedImageFile = $false
  if ($generatedImagePath) {
    $hasGeneratedImageFile = Test-Path -LiteralPath $generatedImagePath -ErrorAction SilentlyContinue
  }

  $generatedTitle = [string]$record.generatedTitle
  $body = [string]$record.body
  if ($generatedTitle.Length -gt 90) {
    throw "generatedTitle is too long ($($generatedTitle.Length) chars) for URL $($record.sourceUrl). Keep it under 90 characters."
  }
  if ($generatedTitle -match "(\.\.\.|\u2026)$") {
    throw "generatedTitle looks truncated for URL $($record.sourceUrl). Rewrite it as a complete headline."
  }
  if ($body.Length -lt 3500 -or $body.Length -gt 5000) {
    throw "body must be 700-900 words (approximately 3,500-5,000 characters) for URL $($record.sourceUrl). Current length: $($body.Length)."
  }
  if ($body -match "(?i)^\s*(A report from|According to the source|This story fits)\b") {
    throw "body starts like an internal summary for URL $($record.sourceUrl). Rewrite it as a formal news article."
  }
  if ($body -match "\[\+?\d+\s+chars\]") {
    throw "body still contains a GNews truncation suffix for URL $($record.sourceUrl). Remove it and rewrite the article."
  }

  $publishedAt = if ($record.publishedAt) { [string]$record.publishedAt } else { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
  # Keep select fields stable across PowerShell/CLI encodings; user JSON only supplies content fields.
  $status = if ($generatedImageUrl -or $hasGeneratedImageFile) { $defaultStatus } else { (U "\u5931\u8d25") }
  $publishStatus = $defaultPublishStatus
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
    $generatedTitle,
    $body,
    [string]$record.imagePrompt,
    $generatedImageUrl,
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
$jsonArgPath = Resolve-Path -LiteralPath $outputPath -Relative
$jsonArgPath = $jsonArgPath -replace "\\", "/"
if (-not $jsonArgPath.StartsWith("./") -and -not $jsonArgPath.StartsWith("../")) {
  $jsonArgPath = "./$jsonArgPath"
}

if ($DryRun) {
  Write-Host "Dry run. Payload written to $outputPath"
  Write-Host "Rows: $($rows.Count)"
  exit 0
}

# Resolve lark-cli path: on Windows, lark-cli may be a POSIX shell script that
# PowerShell cannot invoke directly. Fall back to node + @larksuite/cli run.js.
# Also clear NODE_OPTIONS (e.g. --use-system-ca set by sandbox) which can crash node.
if (-not $LarkCli) {
  $resolved = Get-Command lark-cli -ErrorAction SilentlyContinue
  if ($null -eq $resolved) {
    throw "lark-cli not found. Set LARK_CLI or pass -LarkCli with the full path."
  }
  $LarkCli = Resolve-ExistingCommandPath -CommandInfo $resolved
}

if (-not $LarkCli) {
  throw "Unable to resolve a usable lark-cli path."
}

if (-not (Test-Path -LiteralPath $LarkCli -ErrorAction SilentlyContinue)) {
  throw "lark-cli path not found: $LarkCli"
}

$cliArgsList = @(
  "base",
  "+record-batch-create",
  "--base-token", $BaseToken,
  "--table-id", $TableId,
  "--as", "user",
  "--json", "@$jsonArgPath"
)

$createResult = Invoke-LarkCli -LarkCliPath $LarkCli -Arguments $cliArgsList
$cliText = $createResult.Text
if ($cliText) {
  Write-Output $cliText
}

if ($createResult.ExitCode -ne 0) {
  throw "lark-cli failed with exit code $($createResult.ExitCode)."
}

try {
  $cliJson = $cliText | ConvertFrom-Json
  if ($cliJson.PSObject.Properties["ok"] -and -not $cliJson.ok) {
    $message = if ($cliJson.error.message) { $cliJson.error.message } else { "lark-cli returned ok=false." }
    throw $message
  }
} catch [System.ArgumentException] {
  # Non-JSON output is acceptable as long as lark-cli exited successfully.
}

$recordIds = @()
if ($cliJson -and $cliJson.data -and $cliJson.data.record_id_list) {
  $recordIds = @($cliJson.data.record_id_list)
}

for ($i = 0; $i -lt $records.Count; $i++) {
  $record = $records[$i]
  $recordId = if ($i -lt $recordIds.Count) { [string]$recordIds[$i] } else { "" }
  $generatedImagePath = if ($record.generatedImagePath) { [string]$record.generatedImagePath } else { "" }

  if (-not $recordId -or -not $generatedImagePath) {
    continue
  }
  if (-not (Test-Path -LiteralPath $generatedImagePath)) {
    Write-Warning ("Generated image file not found for record {0}: {1}" -f $recordId, $generatedImagePath)
    continue
  }

  $uploadArgs = @(
    "base",
    "+record-upload-attachment",
    "--base-token", $BaseToken,
    "--table-id", $TableId,
    "--record-id", $recordId,
    "--field-id", (U "\u56fe\u7247"),
    "--file", (Get-RelativeCliPath -Path $generatedImagePath),
    "--as", "user"
  )
  $uploadResult = Invoke-LarkCli -LarkCliPath $LarkCli -Arguments $uploadArgs
  if ($uploadResult.Text) {
    Write-Output $uploadResult.Text
  }
  if ($uploadResult.ExitCode -ne 0) {
    throw "Attachment upload failed for record $recordId with exit code $($uploadResult.ExitCode)."
  }
}
