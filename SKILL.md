---
name: gnews-to-lark-base
description: Use when the user wants to fetch international news with GNews API, filter news from the previous 7 days, generate scored Chinese article content and image prompts, and write records into the configured Feishu/Lark Base table using lark-cli. Weekly task producing 25 articles per category (100 total).
---

# GNews To Lark Base

Use this skill for the news automation pipeline that combines **GNews API** (free, global 80K+ sources) and `lark-cli`.

GNews API Key: `ebc3f32f8ed3f49c5a25ac145cb55ed7`
Free tier: 100 requests/day, max 10 articles per request.

Default target:

- Base token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table id: `tblIDJ3Nv9Q2roXL`
- View id: `vewwG9FgZu`
- Categories: `科技AI`, `娱乐体育`, `旅游`, `美食`
- **Fixed output**: 25 articles per category per week, 100 total

## Workflow

1. Confirm GNews API key is valid:
   ```powershell
   $response = Invoke-RestMethod -Uri "https://gnews.io/api/v4/top-headlines?category=general&lang=en&max=1&apikey=ebc3f32f8ed3f49c5a25ac145cb55ed7"
   $response.totalArticles
   ```
2. For each category, fetch news using multiple requests. The strategy differs by category (see `references/category-rules.md` for full rules):

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

   ### 旅游 — 5 requests (50 candidates)

   | # | Type | Query | max |
   |---|------|-------|-----|
   | 1 | search | `travel OR tourism` | 10 |
   | 2 | search | `airline OR flight` | 10 |
   | 3 | search | `hotel OR resort` | 10 |
   | 4 | search | `cruise OR vacation` | 10 |
   | 5 | search | `destination OR tourist attraction` | 10 |
   | 🔧 backup | search | `visa OR passport OR travel policy` | 10 |

   ### 美食 — 5 requests (50 candidates)

   | # | Type | Query | max |
   |---|------|-------|-----|
   | 1 | search | `food OR restaurant` | 10 |
   | 2 | search | `cooking OR recipe` | 10 |
   | 3 | search | `food trend OR diet` | 10 |
   | 4 | search | `cuisine OR chef` | 10 |
   | 5 | search | `wine OR coffee OR dessert` | 10 |
   | 🔧 backup | search | `street food OR food festival` | 10 |

   **Total: 25 requests per run (250 candidates), plus up to 4 backup requests if needed.**

   **Important keyword rules for GNews search**:
   - GNews search engine is NOT like Google Search. Overly narrow queries (e.g. `AI tools OR ChatGPT OR LLM launch`) return **0 results**.
   - Use **moderately broad, natural phrases** that GNews can match: `artificial intelligence`, `sports`, `travel OR tourism`.
   - Combine 2-4 terms with `OR`. Do NOT use 5+ terms or very specific product names.
   - Test new keywords with `max=1` first if unsure.

   Example PowerShell:
   ```powershell
   # 科技AI - headlines
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/top-headlines?category=technology&lang=en&max=10&from=<FROM>&to=<TO>&apikey=ebc3f32f8ed3f49c5a25ac145cb55ed7"

   # 科技AI - search AI
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/search?q=artificial intelligence OR AI&lang=en&max=10&from=<FROM>&to=<TO>&apikey=ebc3f32f8ed3f49c5a25ac145cb55ed7"

   # 娱乐体育 - headlines entertainment
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/top-headlines?category=entertainment&lang=en&max=10&from=<FROM>&to=<TO>&apikey=ebc3f32f8ed3f49c5a25ac145cb55ed7"

   # 娱乐体育 - headlines sports
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/top-headlines?category=sports&lang=en&max=10&from=<FROM>&to=<TO>&apikey=ebc3f32f8ed3f49c5a25ac145cb55ed7"

   # 旅游 - search
   Invoke-RestMethod -Uri "https://gnews.io/api/v4/search?q=travel OR tourism&lang=en&max=10&from=<FROM>&to=<TO>&apikey=ebc3f32f8ed3f49c5a25ac145cb55ed7"
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
   - pass threshold: total score >= 20
6. **Select top 25 per category**: For each category, sort all passed items by total score (descending), take the top 25.
   - If a category has fewer than 25 passed items, trigger the **backup search** for that category (1 extra request, 10 more candidates), then re-score and re-rank.
   - If still under 25 after backup, write all passed items and note the shortfall in the output summary.
   - Do NOT trigger more than 1 backup request per category.
7. For selected items ONLY, fetch the full article content if needed (using the `url` from GNews), then generate:
   - Chinese title
   - Chinese body, 600-800 Chinese characters
   - image prompt, 16:9 cover, no text/watermark
8. Write records to Feishu Base with `scripts/write_lark_records.ps1`.
9. Mark failed or rejected items as `失败` only when the user wants audit rows; otherwise skip them.

## API Rate Limiting & Retry

GNews free tier has strict rate limits. Follow these rules:

- **Wait at least 6 seconds between consecutive API requests**. Use `Start-Sleep -Seconds 6` in PowerShell.
- With 25 requests per run, a full run takes ~150 seconds (2.5 minutes) minimum, plus up to 4 backup requests.
- If you receive HTTP 429 (Too Many Requests):
  1. Wait 30 seconds (`Start-Sleep -Seconds 30`)
  2. Retry the same request **once**
  3. If 429 again, skip that request and log the failure in the output summary
- **Do NOT remove `country` parameter** — but prefer omitting it or using multiple countries in rotation rather than always `country=us`

## Source Rules

Read `references/category-rules.md` before deciding keywords or source filters.

The hard time window is **previous 7 days** relative to the trigger time. Both the API `from` parameter and step 3 pre-filter enforce this 7-day window.

When calling GNews API, always include date range (`from`/`to` parameters). GNews returns standard JSON with fields: `title`, `description`, `content`, `url`, `image`, `publishedAt`, `source.name`.

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
| **# AI评分** | Total score number ONLY | `24` |
| **AI评价内容** | Detailed breakdown + reason | `"相关性8，新颖性8，完整度8。通过原因：..."` |

- `AI评分` must be a plain integer (e.g., `20`, `24`, `27`)
- `AI评价内容` holds the full text with per-dimension scores and reasoning

## Writing To Lark Base

Use `lark-cli base +record-batch-create` through the bundled script:

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

- number of GNews candidates fetched per category
- number kept after pre-filter
- number passed score threshold
- number selected (top 25 or fewer)
- number written to Feishu Base
- any categories with shortfall (< 25 articles)
- any API or permission failures (including 429 rate limit hits)
- total API requests consumed vs daily quota

Do not claim images are attached unless an image generation step and attachment upload have actually run.
