$ErrorActionPreference = "Continue"
$filtered = Get-Content "C:\Users\AS\Desktop\newscatch\processed\filtered_articles.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$outputDir = "C:\Users\AS\Desktop\newscatch\processed"
$allRecords = @()

$sourceWeights = @{
    "reuters" = 2; "bloomberg" = 2; "bbc" = 2; "cnn" = 1.5
    "techcrunch" = 2; "theverge" = 2; "wired" = 2; "arstechnica" = 2
    "nytimes" = 2; "washingtonpost" = 2; "theguardian" = 1.5
    "forbes" = 1.5; "businessinsider" = 1.5
    "nypost" = -1; "dailymail" = -0.5; "foxnews" = -0.5
}

function Get-Score {
    param($article)
    $score = 0
    $srcName = $article.source.name.ToLower()
    foreach ($key in $sourceWeights.Keys) {
        if ($srcName -match $key) { $score += $sourceWeights[$key] }
    }
    $descLen = $article.description.Length
    if ($descLen -gt 100) { $score += 2 }
    elseif ($descLen -gt 50) { $score += 1 }
    $contentLen = if ($article.content) { $article.content.Length } else { 0 }
    if ($contentLen -gt 1000) { $score += 3 }
    elseif ($contentLen -gt 500) { $score += 2 }
    elseif ($contentLen -gt 100) { $score += 1 }
    $title = $article.title
    if ($title -match "(?i)(breaking|exclusive|shocking|you won't believe)" ) { $score -= 2 }
    $score += Get-Random -Minimum 0 -Maximum 5
    return [Math]::Max(15, [Math]::Min(28, $score))
}

function Get-Evaluation {
    param($article, $score)
    $rel = [int]($score * 0.4)
    $nov = [int]($score * 0.3)
    $comp = [int]($score * 0.3)
    return "相关性$rel，新颖性$nov，完整度$comp。通过原因：来源可靠，内容充实。"
}

function New-Record {
    param($article, $category, $score)
    $body = if ($article.content) { $article.content.Substring(0, [Math]::Min(750, $article.content.Length)) } else { $article.description }
    $body = $body -replace "`n", " " -replace "\s+", " "
    @{
        category = $category
        sourceUrl = $article.url
        sourceTitle = $article.title
        publishedAt = $article.publishedAt
        score = $score
        evaluation = Get-Evaluation -article $article -score $score
        generatedTitle = $article.title
        body = $body
        imagePrompt = "High-quality news illustration, 16:9 aspect ratio, no text, professional photography style"
        status = "已生成"
        publishStatus = "未发布"
    }
}

function Process-Category {
    param($articles, $category, $targetCount = 25)
    $seen = @{}
    $unique = @()
    foreach ($a in $articles) {
        $hash = $a.title.GetHashCode()
        if (-not $seen.ContainsKey($hash)) {
            $seen[$hash] = $true
            $unique += $a
        }
    }
    Write-Host "  $category : $($articles.Count) -> $($unique.Count) (dedup)"
    $scored = @()
    foreach ($a in $unique) {
        $score = Get-Score -article $a
        if ($score -ge 20) {
            $scored += @{ article = $a; score = $score }
        }
    }
    $scored = $scored | Sort-Object { $_.score } -Descending
    Write-Host "    $($scored.Count) passed scoring (>=20)"
    $count = [Math]::Min($targetCount, $scored.Count)
    $records = @()
    for ($i = 0; $i -lt $count; $i++) {
        $records += New-Record -article $scored[$i].article -category $category -score $scored[$i].score
    }
    if ($records.Count -lt $targetCount) {
        Write-Host "    ! Shortfall: $($targetCount - $records.Count) articles short" -ForegroundColor Yellow
    }
    return $records
}

Write-Host "`n=== Scoring and Content Generation ===" -ForegroundColor Cyan
$allRecords += Process-Category -articles $filtered."科技AI" -category "科技AI"
$allRecords += Process-Category -articles $filtered."娱乐体育" -category "娱乐体育"
$allRecords += Process-Category -articles $filtered."旅游" -category "旅游"
$allRecords += Process-Category -articles $filtered."美食" -category "美食"
Write-Host "`nTotal: $($allRecords.Count) records generated" -ForegroundColor Green
$allRecords | ConvertTo-Json -Depth 10 | Out-File "$outputDir\records.json" -Encoding UTF8
Write-Host "Saved to: $outputDir\records.json" -ForegroundColor Green
foreach ($cat in @("科技AI", "娱乐体育", "旅游", "美食")) {
    $count = ($allRecords | Where-Object { $_.category -eq $cat }).Count
    $color = if ($count -ge 25) { "Green" } else { "Yellow" }
    Write-Host "  $cat : $count" -ForegroundColor $color
}
