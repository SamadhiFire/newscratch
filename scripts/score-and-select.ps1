param(
  [string]$InputJson = ".\processed\filtered_articles.json",
  [string]$OutputJson = ".\processed\generation-input.json",
  [string]$SummaryJson = ".\processed\score-summary.json",
  [int]$TargetPerCategory = 25
)

$ErrorActionPreference = "Stop"

function U {
  param([Parameter(Mandatory = $true)][string]$Text)
  return [System.Text.RegularExpressions.Regex]::Unescape($Text)
}

$statusReadyForGeneration = U "\u5f85\u751f\u6210"
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
    keywords = @("celebrity", "movie", "film", "box office", "football", "soccer", "basketball", "nba", "tennis", "golf", "olympics", "racing", "sports", "match", "tournament", "league")
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
  },
  @{
    key = "music"
    name = U "\u97f3\u4e50"
    english = "Music"
    threshold = 18
    keywords = @("music", "musician", "singer", "artist", "concert", "tour", "album", "single", "ep", "billboard", "chart", "streaming", "grammy", "festival", "lineup", "band", "orchestra", "composer", "record label", "soundtrack")
  },
  @{
    key = "life"
    name = U "\u751f\u6d3b"
    english = "Lifestyle and daily living"
    threshold = 18
    keywords = @("wellness", "healthy living", "nutrition", "budget meal", "superfood", "sleep", "stress", "mental health", "family", "household", "cleaning", "home remedy", "chronic disease", "work injury", "stretching", "self care", "safety", "health scam")
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

function Resolve-OutputPath {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path (Get-Location) $Path)
}

function Clean-NewsText {
  param([string]$Text)
  $clean = Normalize-Whitespace -Text $Text
  if (-not $clean) { return "" }

  $clean = $clean -replace "^(?i)(synopsis|article content|tech news news|business news|world news|sports news|entertainment news)\s*:?\s*", ""
  $clean = $clean -replace "(?i)\bBy\s+[A-Za-z0-9 .&_-]+\.com\s+", ""
  $clean = $clean -replace "(?i)\bBy\s+CNBCTV18\.com\s+", ""
  $clean = $clean -replace "(?i)\bComments\s+Stock index futures\b", "Stock index futures"
  $clean = $clean -replace "\s*(\.{3}|\u2026)\s*$", ""

  return (Normalize-Whitespace -Text $clean)
}

function Strip-GNewsSuffix {
  param([string]$Text)
  return (Clean-NewsText -Text ((Get-Text $Text) -replace "\s*\[\+?\d+\s+chars\]\s*$", ""))
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
  return ""
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
$selectedArticles = @()
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
    $sourceBody = Strip-GNewsSuffix -Text (Get-Text $article.content)
    if (-not $sourceBody) { $sourceBody = Strip-GNewsSuffix -Text (Get-Text $article.description) }
    $sourceDescription = Strip-GNewsSuffix -Text (Get-Text $article.description)
    $reason = "source is timely, category match is sufficient, and the available GNews summary has enough detail for model rewriting"

    $selectedArticles += [ordered]@{
      category = $config.name
      categoryKey = $config.key
      categoryEnglish = $config.english
      sourceUrl = Get-Text $article.url
      sourceTitle = Strip-GNewsSuffix -Text (Get-Text $article.title)
      sourceDescription = $sourceDescription
      sourceBody = $sourceBody
      sourceImage = Get-Text $article.image
      sourceName = Get-SourceName -Article $article
      publishedAt = (Get-ArticleDate -Article $article).ToString("yyyy-MM-dd HH:mm:ss")
      score = $breakdown.total
      evaluation = New-Evaluation -Breakdown $breakdown -Reason $reason
      status = $statusReadyForGeneration
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

$outputPath = Resolve-OutputPath -Path $OutputJson
$summaryPath = Resolve-OutputPath -Path $SummaryJson

$outputParent = Split-Path -Parent $outputPath
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) {
  New-Item -ItemType Directory -Path $outputParent | Out-Null
}

$summaryParent = Split-Path -Parent $summaryPath
if ($summaryParent -and -not (Test-Path -LiteralPath $summaryParent)) {
  New-Item -ItemType Directory -Path $summaryParent | Out-Null
}

$articlesJson = ConvertTo-Json -InputObject @($selectedArticles) -Depth 12
$summaryJsonText = ConvertTo-Json -InputObject $summary -Depth 12
[System.IO.File]::WriteAllText($outputPath, $articlesJson, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($summaryPath, $summaryJsonText, [System.Text.UTF8Encoding]::new($false))

Write-Host "Selected articles for model generation: $($selectedArticles.Count)"
Write-Host "Saved generation input to: $OutputJson"
Write-Host "Saved score summary to: $SummaryJson"
foreach ($config in $categoryConfigs) {
  $catSummary = $summary[$config.name]
  Write-Host ("  {0}: candidates={1}, passed={2}, selected={3}, shortfall={4}" -f $config.name, $catSummary.candidates, $catSummary.passed, $catSummary.selected, $catSummary.shortfall)
}
