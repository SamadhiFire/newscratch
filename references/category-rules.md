# Category And Source Rules

## Hard Rules

- Only use news published within the previous **7 days** relative to the run or trigger time (weekly task).
  - The GNews API `from` parameter is set to 7 days ago; items older than 7 days are filtered out in pre-filtering as a safety check.
- Every accepted item must have a real source URL.
- Reject or mark failed if publish time is missing, vague, or older than 7 days.
- Do not invent source title, URL, publish time, or quoted facts.
- **Fixed output per category**: top 25 articles ranked by score. If fewer than 25 pass the threshold, trigger backup search (1 extra request). If still under 25 after backup, write all passed items and note the shortfall.
- Total weekly output: 4 categories × 25 = 100 articles.

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

**GNews request strategy**: search only — 5 requests (50 candidates)

| # | Type | Query | max |
|---|------|-------|-----|
| 1 | search | `travel OR tourism` | 10 |
| 2 | search | `airline OR flight` | 10 |
| 3 | search | `hotel OR resort` | 10 |
| 4 | search | `cruise OR vacation` | 10 |
| 5 | search | `destination OR tourist attraction` | 10 |
| 🔧 backup | search | `visa OR passport OR travel policy` | 10 |

NO headlines — GNews has no travel category; `category=general` returns political news.

Prefer policy updates, destination changes, route changes, seasonal travel trends, and useful travel information.

### 美食

**GNews request strategy**: search only — 5 requests (50 candidates)

| # | Type | Query | max |
|---|------|-------|-----|
| 1 | search | `food OR restaurant` | 10 |
| 2 | search | `cooking OR recipe` | 10 |
| 3 | search | `food trend OR diet` | 10 |
| 4 | search | `cuisine OR chef` | 10 |
| 5 | search | `wine OR coffee OR dessert` | 10 |
| 🔧 backup | search | `street food OR food festival` | 10 |

NO headlines — same reason as 旅游.

Prefer information that can become practical food content, local dining news, or trend analysis.

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
- Pass threshold: `>= 20`
- **Selection**: For each category, sort passed items by total score descending, take top 25.

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
