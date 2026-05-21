# Category And Source Rules

## 2026-05-21 Optimization Update

Based on dry-run findings, this pipeline was optimized:

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| 旅游/美食 only got 10-20 articles | No headlines category + 5 requests insufficient | Increased to **8 requests** each |
| 4+ 429 errors per 美食 | Popular generic keywords (food, restaurant) hit rate limit fast | Split into **specific diverse keywords** |
| 旅游 got 3 429 errors | Overlapping keywords (travel, tourism, vacation) | New keywords: backpacking, digital nomad, national park |
| 旅游/美食 shortfall after scoring | Low base content density | **Adaptive threshold**: 旅游/美食 >= 18 (vs 20) |

**Total requests increased**: 25 → 31 per run. Runtime: 2.5 min → 6-8 min.

## Hard Rules

- Only use news published within the previous **7 days** relative to the run or trigger time (weekly task).
  - The GNews API `from` parameter is set to 7 days ago; items older than 7 days are filtered out in pre-filtering as a safety check.
- Every accepted item must have a real source URL.
- Reject or mark failed if publish time is missing, vague, or older than 7 days.
- Do not invent source title, URL, publish time, or quoted facts.
- **Fixed output per category**: top 25 articles ranked by score. If fewer than 25 pass the threshold, trigger backup search (1 extra request). If still under 25 after backup, write all passed items and note the shortfall.
- Total weekly output: 4 categories × 25 = 100 articles.

## Request Staggering (Required)

> **Always stagger requests across categories**, not batch by category.

Correct order (8-10s between each):
```
科技AI R1 → 娱乐体育 R1 → 娱乐体育 R2 → 旅游 R1 → 美食 R1 → 科技AI R2 → 娱乐体育 R3 → 旅游 R2 → 美食 R2 → ...
```

Running all 旅游 requests consecutively = 429 guaranteed. Round-robin prevents rate limit concentration.

## Categories

### 科技AI

**GNews request strategy**: 1 headlines + 6 search = 7 requests (70 candidates)

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

⚠️ Do NOT use overly narrow queries like `AI tools OR ChatGPT OR LLM launch` — GNews search returns 0 results for these.

Prefer practical content that can become a useful tutorial, tool explanation, or product update article.

### 娱乐体育

**GNews request strategy**: 2 headlines (entertainment + sports) + 6 search = 8 requests (80 candidates)

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

**Content policy**: Gossip, celebrity news, and entertainment rumors are welcome. Only exclude content with no source or pure fabrication. This category covers both entertainment (movies, music, celebrity) and sports (football, basketball, tennis, Olympics, etc.).

### 旅游

**GNews request strategy**: search only — **8 requests (80 candidates)** ← Optimized from 5

> No headlines category available. Use diverse, specific keywords to avoid 429 concentration on popular queries.

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

NO headlines — GNews has no travel category; `category=general` returns political news.

Prefer policy updates, destination changes, route changes, seasonal travel trends, and useful travel information.

**Why these keywords?** Previous run used `travel OR tourism` / `airline OR flight` — these popular queries hit 429 faster. Diverse specific queries return fewer but higher-quality results per query, reducing 429 concentration.

### 美食

**GNews request strategy**: search only — **8 requests (80 candidates)** ← Optimized from 5

> No headlines category available. Split generic queries into specific niches.

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

NO headlines — same reason as 旅游.

Prefer information that can become practical food content, local dining news, or trend analysis.

**Why these keywords?** Previous run used `food OR restaurant` — too broad, too popular, triggered 429 on every request. Niche queries like `michelin star OR food award` return specialized content that scores higher and avoids 429.

## GNews Keyword Guidelines

GNews search engine behaves differently from Google Search:

| ❌ Bad (returns 0 results) | ✅ Good (returns results) |
|---|---|
| `AI tools OR ChatGPT OR LLM launch` | `artificial intelligence OR AI startup` |
| `food trend OR restaurant opening` | `food OR restaurant OR cuisine` |
| `travel trend OR airline route OR tourism policy` | `travel OR tourism OR airline` |

Rules:
- Use **moderately broad, natural phrases** that GNews can match
- Combine 2-4 terms with `OR`; do NOT use 5+ terms
- Avoid very specific product names (ChatGPT, Cursor) as standalone search terms
- Test new keywords with `max=1` first if unsure

## Scoring

Score total is `relevance + novelty + completeness`.

- Relevance: 0-10
- Novelty: 0-10
- Completeness: 0-10

**Adaptive pass threshold** (optimized 2026-05-21):

| Category | Threshold | Reason |
|----------|-----------|--------|
| 科技AI | >= 20 | Headlines + 7 search requests = high content density |
| 娱乐体育 | >= 20 | Headlines + 8 search requests = high content density |
| 旅游 | >= 18 | Search only, no headlines category, lower density |
| 美食 | >= 18 | Search only, no headlines category, lower density |

**Selection**: For each category, sort passed items by total score descending, take top 25.

If the source is outside the 7-day window or lacks a reliable URL, score `0`.

## Backup Search (Shortfall Handling)

If a category has fewer than 25 passed items after initial scoring:
1. Trigger the category's backup search (1 extra API request, max=10)
2. Pre-filter and score the new candidates
3. Re-rank all passed items and take top 25
4. If still under 25, write all passed items and note the shortfall in the output summary
5. Do NOT trigger more than 1 backup request per category per run

## Source Blacklist

Always reject articles from these sources:

- `TMZ` (privacy-violating paparazzi content, legal risk)
- Any source whose `source.name` contains words like: `Crypto`, `Bet`, `Gambling`, `Casino`, `Forex`, `DraftKings`, `Polymarket`

**Not blacklisted**: Newsweek, Fox News, Daily Mail — these are valid sources. Gossip and entertainment content is welcome for the 娱乐体育 category.
