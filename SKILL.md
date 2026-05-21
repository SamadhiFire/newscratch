---
name: gnews-to-lark-base
description: Use when the user wants to fetch international news with GNews API, filter news from the previous 7 days, generate scored English article content and image prompts, and write records into the configured Feishu/Lark Base table using lark-cli. Weekly task producing 25 articles per category (100 total).
---

# GNews To Lark Base

Use this skill for the news automation pipeline that combines **GNews API** (free, global 80K+ sources) and `lark-cli`.

GNews API Key: read from `GNEWS_API_KEY` or pass `-ApiKey` to `scripts/fetch-gnews.ps1`.
Free tier: 100 requests/day, max 10 articles per request.

Default target:

- Base token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table id: `tblIDJ3Nv9Q2roXL`
- View id: `vewwG9FgZu`
- Categories: `科技AI`, `娱乐体育`, `旅游`, `美食`
- **Fixed output**: 25 articles per category per week, 100 total

## Workflow

> **Optimization Notes** (from 2026-05-21 run):
> - 旅游/美食 have NO headlines category → rely entirely on search → need MORE requests (8 vs 5)
> - GNews 429 errors spike when running multiple same-type queries consecutively → stagger requests across categories
> - 旅游/美食 content is inherently harder to score → use adaptive threshold (≥18 for these categories)
> - Keywords must be diverse — overlapping terms cause 429 to hit harder on popular queries

1. Confirm the request plan and GNews API key:
   ```powershell
   $env:GNEWS_API_KEY = "your-gnews-api-key"
   .\scripts\fetch-gnews.ps1 -DryRun
   ```
2. For each category, fetch news using multiple requests with `scripts/fetch-gnews.ps1`. **Stagger requests across categories** to avoid 429:
   - Run 1 request per category in round-robin (not all requests for one category at once)
   - Always wait 8-10 seconds between requests (increased from 6s to reduce 429)
   - See `references/category-rules.md` for full optimized rules:

   ### 科技AI — 7 requests (70 candidates)

   | # | Type | Query | max |
   |---|------|-------|-----|
   | 1 | headlines | `category=technology` | 10 |
   | 2 | search | `artificial intelligence OR AI` | 10 |
   | 3 | search | `AI startup OR tech company` | 10 |
   | 4 | search | `chip OR semiconductor OR smartphone` | 10 |
   | 5 | search | `space OR robot OR quantum` | 10 |
   | 6 | search | `cybersecurity OR data breach` | 10 |
   | 7 | search | `software OR app OR cloud` | 10 |
   | 🔧 backup | search | `electric vehicle OR battery OR self-driving` | 10 |

   ### 娱乐体育 — 8 requests (80 candidates)

   | # | Type | Query | max |
   |---|------|-------|-----|
   | 1 | headlines | `category=entertainment` | 10 |
   | 2 | headlines | `category=sports` | 10 |
   | 3 | search | `celebrity OR star OR gossip` | 10 |
   | 4 | search | `movie OR film OR box office` | 10 |
   | 5 | search | `music OR concert OR album` | 10 |
   | 6 | search | `football OR soccer` | 10 |
   | 7 | search | `basketball OR NBA` | 10 |
   | 8 | search | `tennis OR golf OR Olympics OR racing` | 10 |
   | 🔧 backup | search | `video game OR e-sports OR streaming` | 10 |

   ### 旅游 — **8 requests (80 candidates)** ← Optimized from 5

   > No headlines category available. Use diverse, specific keywords to avoid 429 concentration.

   | # | Type | Query | max |
   |---|------|-------|-----|
   | 1 | search | `solo travel OR backpacking` | 10 |
   | 2 | search | `airport OR flight delay OR airline` | 10 |
   | 3 | search | `hotel OR resort OR accommodation` | 10 |
   | 4 | search | `tourist destination OR travel guide` | 10 |
   | 5 | search | `budget travel OR luxury travel` | 10 |
   | 6 | search | `digital nomad OR remote work travel` | 10 |
   | 7 | search | `cruise ship OR travel deal` | 10 |
   | 8 | search | `national park OR adventure travel` | 10 |
   | 🔧 backup | search | `visa OR passport OR travel policy` | 10 |

   ### 美食 — **8 requests (80 candidates)** ← Optimized from 5

   > No headlines category available. Use diverse keywords for coverage.

   | # | Type | Query | max |
   |---|------|-------|-----|
   | 1 | search | `fine dining OR restaurant review` | 10 |
   | 2 | search | `street food OR local cuisine` | 10 |
   | 3 | search | `michelin star OR food award` | 10 |
   | 4 | search | `coffee shop OR bakery OR cafe` | 10 |
   | 5 | search | `food trend OR healthy diet` | 10 |
   | 6 | search | `wine tasting OR craft beer` | 10 |
   | 7 | search | `cooking class OR food recipe` | 10 |
   | 8 | search | `food festival OR food market` | 10 |
   | 🔧 backup | search | `dessert OR vegan food OR organic` | 10 |

   **Total: 31 requests per run (310 candidates), plus up to 4 backup requests.**

   > **Why 31 requests?**
   > - 科技AI/娱乐体育 have dedicated headlines categories (1-2 requests each)
   > - 旅游/美食 have NO headlines → need more search queries to compensate
   > - The extra 6 requests for 旅游/美食 reduce 429 concentration on any single query type

   **Important keyword rules for GNews search**:
   - GNews search engine is NOT like Google Search. Overly narrow queries (e.g. `AI tools OR ChatGPT OR LLM launch`) return **0 results**.
   - Use **moderately broad, natural phrases** that GNews can match: `artificial intelligence`, `sports`, `travel OR tourism`.
   - Combine 2-4 terms with `OR`. Do NOT use 5+ terms or very specific product names.
   - Test new keywords with `max=1` first if unsure.

   Example PowerShell:
   ```powershell
   # 科技AI - headlines
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/top-headlines?category=technology&lang=en&max=10&from=<FROM>&to=<TO>&apikey=$env:GNEWS_API_KEY"

   # 科技AI - search AI
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/search?q=artificial intelligence OR AI&lang=en&max=10&from=<FROM>&to=<TO>&apikey=$env:GNEWS_API_KEY"

   # 娱乐体育 - headlines entertainment
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/top-headlines?category=entertainment&lang=en&max=10&from=<FROM>&to=<TO>&apikey=$env:GNEWS_API_KEY"

   # 娱乐体育 - headlines sports
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/top-headlines?category=sports&lang=en&max=10&from=<FROM>&to=<TO>&apikey=$env:GNEWS_API_KEY"

   # 旅游 - search
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/search?q=travel OR tourism&lang=en&max=10&from=<FROM>&to=<TO>&apikey=$env:GNEWS_API_KEY"
   ```

   **Time window parameters**:
   - Set `from` to **7 days ago** and `to` to **now** (ISO 8601 format, e.g. `2026-05-14T09:30:00Z`)
   - This is a weekly task; the previous 7 days of news are in scope
   - All requests use `max=10`

3. **Quick pre-filter** (before scoring): Immediately discard items that:
   - Have empty, generic, or clickbait titles (e.g., "You won't believe...", "Breaking:")
   - Have `description` shorter than 50 characters (too little info to evaluate)
   - Come from sources in the **source blacklist** (see below)
   - Have duplicate URLs or very similar titles (>80% text overlap) with already-seen items
   - **Published more than 7 days ago** (double-check in case GNews returns stale items)
4. **Relevance pre-check**: For each remaining item, do a fast relevance check based on title + description ONLY (do not fetch full article yet):
   - Does the title clearly relate to one of the 4 target categories?
   - Is there enough substance (not just a headline/teaser)?
   - Discard items that clearly do not fit any category.
5. Score each remaining item:
   - relevance 0-10
   - novelty 0-10
   - completeness 0-10
   - **Total score** = sum of above three dimensions
   - **Pass threshold** (adaptive per category):
     - 科技AI / 娱乐体育: **>= 20**
     - 旅游 / 美食: **>= 18** (lower — these categories have inherently lower content density without headlines category)
6. **Select top 25 per category**: For each category, sort all passed items by total score (descending), take the top 25.
   - If a category has fewer than 25 passed items, trigger the **backup search** for that category (1 extra request, 10 more candidates), then re-score and re-rank.
   - If still under 25 after backup, write all passed items and note the shortfall in the output summary.
   - Do NOT trigger more than 1 backup request per category.
7. For selected items ONLY, **generate English publication content**:
   > ⚠️ **CRITICAL**: Both "优化后标题" and "优化后正文" must be **AI-generated from scratch**, NOT copied from the original GNews fields.
   >
   > ❌ Wrong title: `Up to 200 staff...` (copied from GNews `title`)
   > ✅ Correct title: `Iris Energy to Add 1.4GW in Pennsylvania for AI Data Centers` (rewritten to be complete and informative)
   >
   > ❌ Wrong body: `GitHub says hackers stole data... [+1433 chars]` (raw GNews snippet)
   > ✅ Correct body: A complete, readable English news article (600-1000 characters) that tells the full story

   **Content generation rules**:
   - When running as an agent, generate the title/body with model judgment. The local `scripts/score-and-generate.ps1` fallback creates deterministic publication drafts from the available GNews fields, and should be reviewed before publishing.
   - Read the source article's `title` + `description` + `content` (strip `[+N chars]` suffix)
   - **优化后标题**: Generate a **new, complete English headline** that captures the core story. Do NOT copy the original GNews `title`.
     - Must be a proper headline (not truncated like GNews titles often are)
     - Length: 80-150 characters
     - Example: Original `Star Health w...` → Generated `Star Health Plans 65% Revenue from Tier-2 and Tier-3 Cities by 2030`
   - **优化后正文**: Write a **complete English news article** in professional journalistic style
     - Must be readable as a standalone piece (someone can understand the story without clicking the source link)
     - Length: **600-1000 characters** (not words — characters including spaces)
     - Structure: Lead paragraph (who/what/when) → body detail → context/closing
     - Do NOT copy-paste GNews content directly
     - Do NOT include the `[+N chars]` suffix
   - image prompt, 16:9 cover, no text/watermark

   **Field mapping**:
   | Field | Source | Must be AI-generated? |
   |-------|--------|----------------------|
   | `新闻标题` | Original GNews `title` | ❌ Keep original |
   | `新闻正文` | Original GNews `content` | ❌ Keep original (for reference) |
   | `优化后标题` | **AI-generated English headline** | ✅ **YES — rewrite from scratch** |
   | `优化后正文` | **AI-generated English news article** | ✅ **YES — rewrite from scratch** |
   | `文生图提示词` | AI-generated image prompt | ✅ YES |
8. Write records to Feishu Base with `scripts/write_lark_records.ps1`, or run the full sequence with `scripts/run_pipeline.ps1`.
9. Mark failed or rejected items as `失败` only when the user wants audit rows; otherwise skip them.

## Staggered Request Strategy (Avoid 429)

**Critical optimization**: Running all requests for one category consecutively triggers 429 faster.

**Round-robin fetching** (execute in this order, 8-10s gap between each):

```
Request  1: 科技AI R1 (headlines)
Request  2: 娱乐体育 R1 (headlines entertainment)
Request  3: 娱乐体育 R2 (headlines sports)
Request  4: 旅游 R1
Request  5: 美食 R1
Request  6: 科技AI R2
Request  7: 娱乐体育 R3
Request  8: 旅游 R2
Request  9: 美食 R2
... (continue alternating across categories)
```

This spreads same-keyword queries across time, dramatically reducing 429 hits.

**Why this works**: GNews 429 is triggered by request rate per-keyword. Spacing them out lets the rate limiter cool down.

## API Rate Limiting & Retry

GNews free tier has strict rate limits. Follow these rules:

- **Wait 8-10 seconds between consecutive API requests** (increased from 6s).
- With 31 requests + 4 backup per run, full run takes ~6-8 minutes minimum.
- **429 handling** (adaptive retry):
  1. Wait 30 seconds (`Start-Sleep -Seconds 30`)
  2. Retry the same request **once**
  3. If 429 again, skip that request and log the failure
  4. **Do NOT retry the same query** — move to next request instead
  5. Count skipped requests toward daily quota for tracking
- **Do NOT remove `country` parameter** — but prefer omitting it or using multiple countries in rotation rather than always `country=us`

## Source Rules

Read `references/category-rules.md` before deciding keywords or source filters.

The hard time window is **previous 7 days** relative to the trigger time. Both the API `from` parameter and step 3 pre-filter enforce this 7-day window.

When calling GNews API, always include date range (`from`/`to` parameters). GNews returns standard JSON with fields: `title`, `description`, `content`, `url`, `image`, `publishedAt`, `source.name`.

**⚠️ Content field caveat**: GNews `content` is truncated for free tier users and ends with `[+N chars]` (e.g. `...release date. [+5122 chars]`). Always strip this suffix via regex before using the content. The actual usable content may be as short as 200-300 characters; fall back to `description` when `content` is too short.

### Source Blacklist

Always reject articles from these sources:

- `TMZ` (privacy-violating paparazzi content, legal risk)
- Any source whose `source.name` contains words like: `Crypto`, `Bet`, `Gambling`, `Casino`, `Forex`, `DraftKings`, `Polymarket`

**Note**: Newsweek, Fox News, and Daily Mail are **NOT** blacklisted. Gossip and entertainment content is welcome for the 娱乐体育 category. Only reject sources that are pure gambling/crypto spam or paparazzi with legal risk.

This list can be extended by the user at any time.

## Scoring & Field Mapping

Two separate fields exist -- do NOT conflate them:

| Field | Content | Example |
|---|---|---|
| **AI评分** | Total score number ONLY | `24` |
| **AI评价内容** | Detailed breakdown + reason | `"相关性8，新颖性8，完整度8。通过原因：..."` |

- `AI评分` must be a plain integer (e.g., `20`, `24`, `27`)
- `AI评价内容` holds the full text with per-dimension scores and reasoning

## Writing To Lark Base

Use the pipeline script for the normal path. It fetches, scores/generates, then creates a Lark dry-run payload unless `-Publish` is provided:

```powershell
.\scripts\run_pipeline.ps1
.\scripts\run_pipeline.ps1 -Publish
```

Use individual scripts when debugging:

```powershell
.\scripts\fetch-gnews.ps1 -DryRun
.\scripts\fetch-gnews.ps1
.\scripts\score-and-generate.ps1 -InputJson .\processed\filtered_articles.json -OutputJson .\records.normalized.json
```

Use `lark-cli base +record-batch-create` through the bundled write script:

```powershell
.\scripts\write_lark_records.ps1 -InputJson .\records.normalized.json
```

Use `-DryRun` first when changing mappings:

```powershell
.\scripts\write_lark_records.ps1 -InputJson .\records.normalized.json -DryRun
```

If sandbox or keychain access blocks `lark-cli`, rerun the command with escalation.

## Output Contract

For each run, summarize:

- **429 impact**: number of 429 errors per category, which requests were skipped
- number of GNews candidates fetched per category
- number kept after pre-filter (dedup + blacklist + 7-day)
- number passed adaptive score threshold
- number selected (top 25 or fewer)
- number written to Feishu Base
- any categories with shortfall (< 25 articles)
- any API or permission failures
- total API requests consumed vs daily quota (100/day)
- **recommendation**: whether date range should be extended for 旅游/美食 next run

Do not claim images are attached unless an image generation step and attachment upload have actually run.
