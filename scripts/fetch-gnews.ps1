param(
  [string]$ApiKey = $env:GNEWS_API_KEY,
  [string]$OutputDir = ".\processed",
  [int]$Days = 7,
  [int]$DelaySeconds = 9,
  [int]$RetryDelaySeconds = 30,
  [int]$MaxArticles = 10,
  [switch]$DryRun,
  [switch]$IncludeBackup,
  [switch]$NoDelay
)

$ErrorActionPreference = "Stop"

function U {
  param([Parameter(Mandatory = $true)][string]$Text)
  return [System.Text.RegularExpressions.Regex]::Unescape($Text)
}

$categories = [ordered]@{
  tech = U "\u79d1\u6280AI"
  entertainment = U "\u5a31\u4e50\u4f53\u80b2"
  travel = U "\u65c5\u6e38"
  food = U "\u7f8e\u98df"
  music = U "\u97f3\u4e50"
  life = U "\u751f\u6d3b"
}

$requestSpecs = [ordered]@{
  tech = @(
    @{ type = "headlines"; category = "technology"; label = "technology headlines" },
    @{ type = "search"; q = "artificial intelligence OR AI"; label = "artificial intelligence OR AI" },
    @{ type = "search"; q = "AI startup OR tech company"; label = "AI startup OR tech company" },
    @{ type = "search"; q = "chip OR semiconductor OR smartphone"; label = "chip OR semiconductor OR smartphone" },
    @{ type = "search"; q = "space OR robot OR quantum"; label = "space OR robot OR quantum" },
    @{ type = "search"; q = "cybersecurity OR data breach"; label = "cybersecurity OR data breach" },
    @{ type = "search"; q = "software OR app OR cloud"; label = "software OR app OR cloud" }
  )
  entertainment = @(
    @{ type = "headlines"; category = "entertainment"; label = "entertainment headlines" },
    @{ type = "headlines"; category = "sports"; label = "sports headlines" },
    @{ type = "search"; q = "celebrity OR star OR gossip"; label = "celebrity OR star OR gossip" },
    @{ type = "search"; q = "movie OR film OR box office"; label = "movie OR film OR box office" },
    @{ type = "search"; q = "football OR soccer"; label = "football OR soccer" },
    @{ type = "search"; q = "basketball OR NBA"; label = "basketball OR NBA" },
    @{ type = "search"; q = "tennis OR golf OR Olympics OR racing"; label = "tennis OR golf OR Olympics OR racing" }
  )
  travel = @(
    @{ type = "search"; q = "solo travel OR backpacking"; label = "solo travel OR backpacking" },
    @{ type = "search"; q = "airport OR flight delay OR airline"; label = "airport OR flight delay OR airline" },
    @{ type = "search"; q = "hotel OR resort OR accommodation"; label = "hotel OR resort OR accommodation" },
    @{ type = "search"; q = "tourist destination OR travel guide"; label = "tourist destination OR travel guide" },
    @{ type = "search"; q = "budget travel OR luxury travel"; label = "budget travel OR luxury travel" },
    @{ type = "search"; q = "digital nomad OR remote work travel"; label = "digital nomad OR remote work travel" },
    @{ type = "search"; q = "cruise ship OR travel deal"; label = "cruise ship OR travel deal" },
    @{ type = "search"; q = "national park OR adventure travel"; label = "national park OR adventure travel" }
  )
  food = @(
    @{ type = "search"; q = "fine dining OR restaurant review"; label = "fine dining OR restaurant review" },
    @{ type = "search"; q = "street food OR local cuisine"; label = "street food OR local cuisine" },
    @{ type = "search"; q = "michelin star OR food award"; label = "michelin star OR food award" },
    @{ type = "search"; q = "coffee shop OR bakery OR cafe"; label = "coffee shop OR bakery OR cafe" },
    @{ type = "search"; q = "food trend OR healthy diet"; label = "food trend OR healthy diet" },
    @{ type = "search"; q = "wine tasting OR craft beer"; label = "wine tasting OR craft beer" },
    @{ type = "search"; q = "cooking class OR food recipe"; label = "cooking class OR food recipe" },
    @{ type = "search"; q = "food festival OR food market"; label = "food festival OR food market" }
  )
  music = @(
    @{ type = "search"; q = "music OR musician OR singer"; label = "music OR musician OR singer" },
    @{ type = "search"; q = "concert OR tour OR live performance"; label = "concert OR tour OR live performance" },
    @{ type = "search"; q = "album OR single OR EP"; label = "album OR single OR EP" },
    @{ type = "search"; q = "billboard OR chart OR streaming"; label = "billboard OR chart OR streaming" },
    @{ type = "search"; q = "grammy OR music award"; label = "grammy OR music award" },
    @{ type = "search"; q = "festival OR headline set OR lineup"; label = "festival OR headline set OR lineup" },
    @{ type = "search"; q = "band OR orchestra OR composer"; label = "band OR orchestra OR composer" },
    @{ type = "search"; q = "music industry OR record label"; label = "music industry OR record label" }
  )
  life = @(
    @{ type = "search"; q = "healthy living OR wellness"; label = "healthy living OR wellness" },
    @{ type = "search"; q = "superfood OR budget meal OR nutrition"; label = "superfood OR budget meal OR nutrition" },
    @{ type = "search"; q = "sleep OR stress relief OR mental resilience"; label = "sleep OR stress relief OR mental resilience" },
    @{ type = "search"; q = "home remedy OR chronic disease advice"; label = "home remedy OR chronic disease advice" },
    @{ type = "search"; q = "workplace injury OR back pain OR stretching"; label = "workplace injury OR back pain OR stretching" },
    @{ type = "search"; q = "family life hack OR home cleaning OR household tips"; label = "family life hack OR home cleaning OR household tips" },
    @{ type = "search"; q = "healthy habit OR daily routine OR self care"; label = "healthy habit OR daily routine OR self care" },
    @{ type = "search"; q = "consumer health warning OR health scam OR family safety"; label = "consumer health warning OR health scam OR family safety" }
  )
}

$backupSpecs = @{
  tech = @{ type = "search"; q = "electric vehicle OR battery OR self-driving"; label = "backup: electric vehicle OR battery OR self-driving" }
  entertainment = @{ type = "search"; q = "video game OR e-sports OR streaming"; label = "backup: video game OR e-sports OR streaming" }
  travel = @{ type = "search"; q = "visa OR passport OR travel policy"; label = "backup: visa OR passport OR travel policy" }
  food = @{ type = "search"; q = "dessert OR vegan food OR organic"; label = "backup: dessert OR vegan food OR organic" }
  music = @{ type = "search"; q = "soundtrack OR score OR music release"; label = "backup: soundtrack OR score OR music release" }
  life = @{ type = "search"; q = "wellness OR family health OR sleep routine"; label = "backup: wellness OR family health OR sleep routine" }
}

function New-PlanItem {
  param(
    [string]$CategoryKey,
    [hashtable]$Spec,
    [int]$RequestNumber,
    [bool]$IsBackup
  )

  [pscustomobject]@{
    categoryKey = $CategoryKey
    categoryName = $categories[$CategoryKey]
    requestNumber = $RequestNumber
    isBackup = $IsBackup
    type = $Spec.type
    headlineCategory = $Spec.category
    query = $Spec.q
    label = $Spec.label
    max = $MaxArticles
  }
}

function New-RequestPlan {
  $plan = @()
  $cursor = @{ tech = 0; entertainment = 0; travel = 0; food = 0; music = 0; life = 0 }
  $seed = @("tech", "entertainment", "entertainment", "travel", "food", "music", "life")
  $roundRobin = @("tech", "entertainment", "travel", "food", "music", "life")
  $number = 1

  foreach ($key in $seed) {
    if ($cursor[$key] -lt $requestSpecs[$key].Count) {
      $plan += New-PlanItem -CategoryKey $key -Spec $requestSpecs[$key][$cursor[$key]] -RequestNumber $number -IsBackup $false
      $cursor[$key]++
      $number++
    }
  }

  $remaining = $true
  while ($remaining) {
    $remaining = $false
    foreach ($key in $roundRobin) {
      if ($cursor[$key] -lt $requestSpecs[$key].Count) {
        $remaining = $true
        $plan += New-PlanItem -CategoryKey $key -Spec $requestSpecs[$key][$cursor[$key]] -RequestNumber $number -IsBackup $false
        $cursor[$key]++
        $number++
      }
    }
  }

  if ($IncludeBackup) {
    foreach ($key in $roundRobin) {
      $plan += New-PlanItem -CategoryKey $key -Spec $backupSpecs[$key] -RequestNumber $number -IsBackup $true
      $number++
    }
  }

  return $plan
}

function Join-QueryString {
  param([hashtable]$Params)
  $pairs = @()
  foreach ($item in $Params.GetEnumerator() | Sort-Object Name) {
    if ($null -ne $item.Value -and [string]$item.Value -ne "") {
      $pairs += ("{0}={1}" -f [uri]::EscapeDataString([string]$item.Name), [uri]::EscapeDataString([string]$item.Value))
    }
  }
  return ($pairs -join "&")
}

function New-GNewsUri {
  param($Request, [string]$FromIso, [string]$ToIso)

  $params = @{
    lang = "en"
    max = $Request.max
    from = $FromIso
    to = $ToIso
    apikey = $ApiKey
  }

  if ($Request.type -eq "headlines") {
    $params.category = $Request.headlineCategory
    return "https://gnews.io/api/v4/top-headlines?$(Join-QueryString -Params $params)"
  }

  $params.q = $Request.query
  return "https://gnews.io/api/v4/search?$(Join-QueryString -Params $params)"
}

function Get-StatusCode {
  param($ErrorRecord)
  try {
    return [int]$ErrorRecord.Exception.Response.StatusCode
  } catch {
    return $null
  }
}

function Invoke-GNewsRequest {
  param($Request, [string]$FromIso, [string]$ToIso)

  $uri = New-GNewsUri -Request $Request -FromIso $FromIso -ToIso $ToIso
  $attempt = 0
  while ($attempt -lt 2) {
    $attempt++
    try {
      $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 45
      return @{
        ok = $true
        statusCode = 200
        totalArticles = $response.totalArticles
        articles = @($response.articles)
        error = $null
        attempts = $attempt
      }
    } catch {
      $statusCode = Get-StatusCode -ErrorRecord $_
      if ($statusCode -eq 429 -and $attempt -eq 1) {
        Write-Warning "429 for $($Request.categoryName) / $($Request.label). Waiting $RetryDelaySeconds seconds, then retrying once."
        if (-not $NoDelay) {
          Start-Sleep -Seconds $RetryDelaySeconds
        }
        continue
      }

      return @{
        ok = $false
        statusCode = $statusCode
        totalArticles = 0
        articles = @()
        error = $_.Exception.Message
        attempts = $attempt
      }
    }
  }
}

function Normalize-Text {
  param([string]$Text)
  if (-not $Text) { return "" }
  return ([regex]::Replace($Text.ToLowerInvariant(), "[^a-z0-9]+", " ")).Trim()
}

function Test-BlacklistedSource {
  param([string]$SourceName)
  if (-not $SourceName) { return $false }
  return $SourceName -match "(?i)(^tmz$|crypto|bet|gambling|casino|forex|draftkings|polymarket)"
}

function Test-ClickbaitTitle {
  param([string]$Title)
  if (-not $Title) { return $true }
  return $Title -match "(?i)(you won'?t believe|shocking|what happened next|breaking:|click here)"
}

function Select-FilteredArticles {
  param(
    [hashtable]$RawByCategory,
    [datetime]$FromUtc
  )

  $seenUrls = @{}
  $seenTitles = @{}
  $filtered = [ordered]@{}
  $summary = [ordered]@{}

  foreach ($key in $categories.Keys) {
    $catName = $categories[$key]
    $kept = @()
    $rejected = @{
      missing = 0
      shortDescription = 0
      blacklisted = 0
      clickbait = 0
      stale = 0
      duplicate = 0
    }

    foreach ($article in @($RawByCategory[$key])) {
      $title = [string]$article.title
      $url = [string]$article.url
      $description = [string]$article.description
      $sourceName = [string]$article.source.name

      if (-not $title -or -not $url -or $url -notmatch "^https?://") {
        $rejected.missing++
        continue
      }
      if (-not $description -or $description.Length -lt 50) {
        $rejected.shortDescription++
        continue
      }
      if (Test-BlacklistedSource -SourceName $sourceName) {
        $rejected.blacklisted++
        continue
      }
      if (Test-ClickbaitTitle -Title $title) {
        $rejected.clickbait++
        continue
      }

      try {
        $published = ([datetimeoffset]::Parse([string]$article.publishedAt)).UtcDateTime
      } catch {
        $rejected.stale++
        continue
      }
      if ($published -lt $FromUtc) {
        $rejected.stale++
        continue
      }

      $urlKey = $url.ToLowerInvariant()
      $titleKey = Normalize-Text -Text $title
      if ($seenUrls.ContainsKey($urlKey) -or $seenTitles.ContainsKey($titleKey)) {
        $rejected.duplicate++
        continue
      }

      $seenUrls[$urlKey] = $true
      $seenTitles[$titleKey] = $true
      $kept += $article
    }

    $filtered[$catName] = $kept
    $summary[$catName] = [ordered]@{
      raw = @($RawByCategory[$key]).Count
      kept = $kept.Count
      rejected = $rejected
    }
  }

  return @{
    filtered = $filtered
    summary = $summary
  }
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$plan = @(New-RequestPlan)
$planPath = Join-Path $OutputDir "request-plan.json"
$plan | ConvertTo-Json -Depth 8 | Out-File -FilePath $planPath -Encoding UTF8

Write-Host "Request plan: $($plan.Count) requests"
Write-Host "Saved plan to: $planPath"

if ($DryRun) {
  Write-Host "Dry run only. No GNews API requests were sent."
  exit 0
}

if (-not $ApiKey) {
  throw "GNews API key is missing. Set GNEWS_API_KEY or pass -ApiKey."
}

$toUtc = (Get-Date).ToUniversalTime()
$fromUtc = $toUtc.AddDays(-1 * $Days)
$fromIso = $fromUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
$toIso = $toUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")

$rawByCategory = @{
  tech = @()
  entertainment = @()
  travel = @()
  food = @()
  music = @()
  life = @()
}
$requestLog = @()

for ($i = 0; $i -lt $plan.Count; $i++) {
  $request = $plan[$i]
  Write-Host ("[{0}/{1}] {2} - {3}" -f ($i + 1), $plan.Count, $request.categoryName, $request.label)
  $result = Invoke-GNewsRequest -Request $request -FromIso $fromIso -ToIso $toIso
  if ($result.ok) {
    $rawByCategory[$request.categoryKey] += @($result.articles)
    Write-Host ("  OK: {0} articles returned" -f @($result.articles).Count)
  } else {
    Write-Warning ("  Failed: status={0}; error={1}" -f $result.statusCode, $result.error)
  }

  $requestLog += [ordered]@{
    requestNumber = $request.requestNumber
    category = $request.categoryName
    label = $request.label
    type = $request.type
    statusCode = $result.statusCode
    ok = $result.ok
    attempts = $result.attempts
    articles = @($result.articles).Count
    error = $result.error
  }

  if (-not $NoDelay -and $i -lt ($plan.Count - 1)) {
    Start-Sleep -Seconds $DelaySeconds
  }
}

$filterResult = Select-FilteredArticles -RawByCategory $rawByCategory -FromUtc $fromUtc
$rawOut = [ordered]@{}
foreach ($key in $categories.Keys) {
  $rawOut[$categories[$key]] = $rawByCategory[$key]
}

$rawPath = Join-Path $OutputDir "raw_articles.json"
$filteredPath = Join-Path $OutputDir "filtered_articles.json"
$summaryPath = Join-Path $OutputDir "fetch-summary.json"

$rawOut | ConvertTo-Json -Depth 12 | Out-File -FilePath $rawPath -Encoding UTF8
$filterResult.filtered | ConvertTo-Json -Depth 12 | Out-File -FilePath $filteredPath -Encoding UTF8

$summary = [ordered]@{
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  from = $fromIso
  to = $toIso
  days = $Days
  requestCount = $plan.Count
  requestLog = $requestLog
  categorySummary = $filterResult.summary
}
$summary | ConvertTo-Json -Depth 12 | Out-File -FilePath $summaryPath -Encoding UTF8

Write-Host "Saved raw articles to: $rawPath"
Write-Host "Saved filtered articles to: $filteredPath"
Write-Host "Saved fetch summary to: $summaryPath"
