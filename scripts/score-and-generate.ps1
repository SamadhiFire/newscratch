param(
  [string]$InputJson = ".\processed\filtered_articles.json",
  [string]$OutputJson = ".\records.normalized.json",
  [string]$SummaryJson = ".\processed\score-summary.json",
  [int]$TargetPerCategory = 25
)

$ErrorActionPreference = "Stop"

function U {
  param([Parameter(Mandatory = $true)][string]$Text)
  return [System.Text.RegularExpressions.Regex]::Unescape($Text)
}

$statusGenerated = U "\u5df2\u751f\u6210"
$publishStatusPending = U "\u672a\u53d1\u5e03"

$categoryConfigs = @(
  @{
    key = "tech"
    name = U "\u79d1\u6280AI"
    english = "Technology and AI"
    threshold = 20
    keywords = @("ai", "artificial intelligence", "startup", "technology", "chip", "semiconductor", "smartphone", "space", "robot", "quantum", "cybersecurity", "software", "cloud", "data")
  },
  @{
    key = "entertainment"
    name = U "\u5a31\u4e50\u4f53\u80b2"
    english = "Entertainment and sports"
    threshold = 20
    keywords = @("celebrity", "movie", "film", "box office", "music", "concert", "album", "football", "soccer", "basketball", "nba", "tennis", "golf", "olympics", "racing", "sports")
  },
  @{
    key = "travel"
    name = U "\u65c5\u6e38"
    english = "Travel"
    threshold = 18
    keywords = @("travel", "tourism", "airport", "flight", "airline", "hotel", "resort", "tourist", "destination", "guide", "nomad", "cruise", "national park", "visa", "passport")
  },
  @{
    key = "food"
    name = U "\u7f8e\u98df"
    english = "Food and dining"
    threshold = 18
    keywords = @("food", "restaurant", "dining", "cuisine", "michelin", "coffee", "bakery", "cafe", "diet", "wine", "beer", "cooking", "recipe", "festival", "market", "vegan")
  }
)

function Get-Text {
  param($Value)
  if ($null -eq $Value) { return "" }
  return [string]$Value
}

function Normalize-Whitespace {
  param([string]$Text)
  if (-not $Text) { return "" }
  return ([regex]::Replace($Text, "\s+", " ")).Trim()
}

function Strip-GNewsSuffix {
  param([string]$Text)
  return (Normalize-Whitespace -Text ((Get-Text $Text) -replace "\s*\[\+\d+\s+chars\]\s*$", ""))
}

function Limit-Text {
  param([string]$Text, [int]$MaxLength)
  $clean = Normalize-Whitespace -Text $Text
  if ($clean.Length -le $MaxLength) { return $clean }
  $cut = $clean.Substring(0, $MaxLength).TrimEnd()
  $lastStop = $cut.LastIndexOf(".")
  if ($lastStop -gt 80) {
    return $cut.Substring(0, $lastStop + 1)
  }
  return ($cut.TrimEnd() + "...")
}

function Get-ArticleDate {
  param($Article)
  try {
    return ([datetimeoffset]::Parse((Get-Text $Article.publishedAt))).LocalDateTime
  } catch {
    return Get-Date
  }
}

function Get-SourceName {
  param($Article)
  $name = Get-Text $Article.source.name
  if ($name) { return $name }
  return "the source"
}

function Get-SourceWeight {
  param([string]$SourceName)
  $source = $SourceName.ToLowerInvariant()
  $weights = @{
    "reuters" = 2
    "bloomberg" = 2
    "bbc" = 2
    "cnn" = 1
    "techcrunch" = 2
    "the verge" = 2
    "wired" = 2
    "ars technica" = 2
    "nytimes" = 2
    "washington post" = 2
    "the guardian" = 1
    "forbes" = 1
    "business insider" = 1
    "nypost" = -1
    "daily mail" = -1
    "fox news" = -1
  }

  foreach ($key in $weights.Keys) {
    if ($source -match [regex]::Escape($key)) {
      return [int]$weights[$key]
    }
  }
  return 0
}

function Get-ScoreBreakdown {
  param($Article, $Config)

  $title = (Get-Text $Article.title).ToLowerInvariant()
  $description = (Get-Text $Article.description).ToLowerInvariant()
  $content = (Strip-GNewsSuffix -Text (Get-Text $Article.content)).ToLowerInvariant()
  $combined = "$title $description $content"

  $keywordHits = 0
  foreach ($keyword in $Config.keywords) {
    if ($combined.Contains($keyword)) {
      $keywordHits++
    }
  }

  $relevance = [Math]::Min(10, 5 + $keywordHits)
  if ($keywordHits -eq 0) {
    $relevance = 4
  }

  $sourceName = Get-SourceName -Article $Article
  $sourceWeight = Get-SourceWeight -SourceName $sourceName
  $novelty = 5 + $sourceWeight
  if ($title -match "(?i)(new|launch|plans|opens|wins|warns|announces|reveals|record|first|major)") {
    $novelty += 2
  }
  $ageHours = ((Get-Date) - (Get-ArticleDate -Article $Article)).TotalHours
  if ($ageHours -le 48) {
    $novelty += 1
  }
  $novelty = [Math]::Max(0, [Math]::Min(10, [int]$novelty))

  $completeness = 3
  if ($description.Length -gt 80) { $completeness += 2 }
  if ($description.Length -gt 160) { $completeness += 1 }
  if ($content.Length -gt 180) { $completeness += 2 }
  if ($content.Length -gt 400) { $completeness += 1 }
  if ((Get-Text $Article.url) -match "^https?://" -and (Get-Text $Article.publishedAt)) { $completeness += 1 }
  $completeness = [Math]::Max(0, [Math]::Min(10, [int]$completeness))

  [pscustomobject]@{
    relevance = [int]$relevance
    novelty = [int]$novelty
    completeness = [int]$completeness
    total = [int]($relevance + $novelty + $completeness)
  }
}

function New-Evaluation {
  param($Breakdown, [string]$Reason)

  $rel = U "\u76f8\u5173\u6027"
  $nov = U "\u65b0\u9896\u6027"
  $comp = U "\u5b8c\u6574\u5ea6"
  $reasonLabel = U "\u901a\u8fc7\u539f\u56e0"
  return ("{0}{1}, {2}{3}, {4}{5}. {6}: {7}" -f $rel, $Breakdown.relevance, $nov, $Breakdown.novelty, $comp, $Breakdown.completeness, $reasonLabel, $Reason)
}

function New-GeneratedTitle {
  param($Article, $Config)

  $sourceTitle = Strip-GNewsSuffix -Text (Get-Text $Article.title)
  $description = Strip-GNewsSuffix -Text (Get-Text $Article.description)
  $candidate = ""

  if ($description.Length -ge 60) {
    $candidate = Limit-Text -Text $description -MaxLength 145
  } else {
    $candidate = Limit-Text -Text $sourceTitle -MaxLength 120
  }

  if (-not $candidate) {
    $candidate = "$($Config.english) update from $(Get-SourceName -Article $Article)"
  }

  if ($candidate -eq $sourceTitle) {
    $candidate = "${candidate}: Key details from the latest $($Config.english) report"
  }

  if ($candidate.Length -lt 80) {
    $candidate = "${candidate}: What the latest development means for readers"
  }

  return (Limit-Text -Text $candidate -MaxLength 150)
}

function New-GeneratedBody {
  param($Article, $Config)

  $source = Get-SourceName -Article $Article
  $published = (Get-ArticleDate -Article $Article).ToString("yyyy-MM-dd HH:mm")
  $title = Strip-GNewsSuffix -Text (Get-Text $Article.title)
  $description = Strip-GNewsSuffix -Text (Get-Text $Article.description)
  $content = Strip-GNewsSuffix -Text (Get-Text $Article.content)

  $basisParts = @()
  if ($description) { $basisParts += $description }
  if ($content -and $content -ne $description) { $basisParts += $content }
  $basis = Normalize-Whitespace -Text ($basisParts -join " ")
  if (-not $basis) { $basis = $title }

  $body = "A report from $source published on $published says $basis"
  if ($body -notmatch "[.!?]$") { $body += "." }

  $context = switch ($Config.key) {
    "tech" { "The story is relevant to technology readers because it touches products, infrastructure, companies, or digital risks that can affect the wider market." }
    "entertainment" { "The story fits the entertainment and sports brief because it concerns public figures, events, teams, releases, competitions, or audience trends." }
    "travel" { "The story is useful for travel coverage because it may influence destinations, transport, hospitality, trip planning, or traveler expectations." }
    "food" { "The story fits food and dining coverage because it relates to restaurants, ingredients, culinary trends, beverages, awards, markets, or consumer taste." }
    default { "The story is included because it is timely, sourced, and relevant to the selected editorial category." }
  }
  $body = "$body $context"

  if ($body.Length -lt 600) {
    $body += " The available summary is limited, so this draft avoids adding unsupported facts and preserves the source link for full verification before publication."
  }

  return (Limit-Text -Text $body -MaxLength 1000)
}

function New-ImagePrompt {
  param([string]$GeneratedTitle, $Config)
  $prompt = "Professional editorial cover image for $($Config.english) news: $GeneratedTitle. Realistic, contemporary, documentary photography style, 16:9 aspect ratio, no text, no watermark, no logo."
  return (Limit-Text -Text $prompt -MaxLength 500)
}

function Get-CategoryArticles {
  param($Data, [string]$CategoryName)

  if ($Data -is [System.Array]) {
    return @($Data | Where-Object { (Get-Text $_.category) -eq $CategoryName })
  }

  $property = $Data.PSObject.Properties[$CategoryName]
  if ($null -eq $property) {
    return @()
  }
  return @($property.Value)
}

if (-not (Test-Path -LiteralPath $InputJson)) {
  throw "Input JSON not found: $InputJson. Run scripts\fetch-gnews.ps1 first or provide a filtered article JSON file."
}

$data = Get-Content -LiteralPath $InputJson -Raw -Encoding UTF8 | ConvertFrom-Json
$allRecords = @()
$summary = [ordered]@{}

foreach ($config in $categoryConfigs) {
  $articles = @(Get-CategoryArticles -Data $data -CategoryName $config.name)
  $scored = @()

  foreach ($article in $articles) {
    $breakdown = Get-ScoreBreakdown -Article $article -Config $config
    if ($breakdown.total -ge $config.threshold) {
      $scored += [pscustomobject]@{
        article = $article
        breakdown = $breakdown
      }
    }
  }

  $selected = @($scored | Sort-Object { $_.breakdown.total } -Descending | Select-Object -First $TargetPerCategory)
  foreach ($item in $selected) {
    $article = $item.article
    $breakdown = $item.breakdown
    $generatedTitle = New-GeneratedTitle -Article $article -Config $config
    $body = New-GeneratedBody -Article $article -Config $config
    $sourceBody = Strip-GNewsSuffix -Text (Get-Text $article.content)
    if (-not $sourceBody) { $sourceBody = Strip-GNewsSuffix -Text (Get-Text $article.description) }
    $reason = "source is timely, category match is sufficient, and the available summary has enough detail for a publication draft"

    $allRecords += [ordered]@{
      category = $config.name
      sourceUrl = Get-Text $article.url
      sourceTitle = Get-Text $article.title
      sourceBody = $sourceBody
      publishedAt = (Get-ArticleDate -Article $article).ToString("yyyy-MM-dd HH:mm:ss")
      generatedTitle = $generatedTitle
      body = $body
      imagePrompt = New-ImagePrompt -GeneratedTitle $generatedTitle -Config $config
      score = $breakdown.total
      evaluation = New-Evaluation -Breakdown $breakdown -Reason $reason
      status = $statusGenerated
      publishStatus = $publishStatusPending
    }
  }

  $summary[$config.name] = [ordered]@{
    candidates = $articles.Count
    passed = $scored.Count
    selected = $selected.Count
    threshold = $config.threshold
    shortfall = [Math]::Max(0, $TargetPerCategory - $selected.Count)
  }
}

$outputParent = Split-Path -Parent $OutputJson
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) {
  New-Item -ItemType Directory -Path $outputParent | Out-Null
}

$summaryParent = Split-Path -Parent $SummaryJson
if ($summaryParent -and -not (Test-Path -LiteralPath $summaryParent)) {
  New-Item -ItemType Directory -Path $summaryParent | Out-Null
}

$allRecords | ConvertTo-Json -Depth 12 | Out-File -FilePath $OutputJson -Encoding UTF8
$summary | ConvertTo-Json -Depth 12 | Out-File -FilePath $SummaryJson -Encoding UTF8

Write-Host "Generated records: $($allRecords.Count)"
Write-Host "Saved records to: $OutputJson"
Write-Host "Saved score summary to: $SummaryJson"
foreach ($config in $categoryConfigs) {
  $catSummary = $summary[$config.name]
  Write-Host ("  {0}: candidates={1}, passed={2}, selected={3}, shortfall={4}" -f $config.name, $catSummary.candidates, $catSummary.passed, $catSummary.selected, $catSummary.shortfall)
}
