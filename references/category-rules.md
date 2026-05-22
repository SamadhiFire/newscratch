# Category And Source Rules

Use these rules when changing fetch keywords, thresholds, or source filters.

## Hard Rules

- Only use articles published within the previous 7 days relative to the run time.
- Every accepted item must have a real source URL.
- Reject items with missing or vague publish time, or publish time older than 7 days.
- Do not invent source title, URL, publish time, or quoted facts.
- Target output: top 25 articles per category, 150 total.
- If fewer than 25 pass in one category, run one backup search for that category and note any remaining shortfall.

## Request Staggering

Always stagger requests across categories. Do not run every query for one category consecutively.

Recommended order:

```text
科技AI R1 -> 娱乐体育 R1 -> 娱乐体育 R2 -> 旅游 R1 -> 美食 R1 -> 音乐 R1 -> 生活 R1
科技AI R2 -> 娱乐体育 R3 -> 旅游 R2 -> 美食 R2 -> 音乐 R2 -> 生活 R2
...continue round-robin
```

Wait 8-10 seconds between requests. On HTTP 429, wait 30 seconds, retry once, then skip the request and continue.

## Categories

### 科技AI

Strategy: 1 headlines request + 6 search requests = 7 requests.

| # | Type | Query | max |
|---|---|---|---|
| 1 | headlines | `category=technology` | 10 |
| 2 | search | `artificial intelligence OR AI` | 10 |
| 3 | search | `AI startup OR tech company` | 10 |
| 4 | search | `chip OR semiconductor OR smartphone` | 10 |
| 5 | search | `space OR robot OR quantum` | 10 |
| 6 | search | `cybersecurity OR data breach` | 10 |
| 7 | search | `software OR app OR cloud` | 10 |
| backup | search | `electric vehicle OR battery OR self-driving` | 10 |

Prefer practical technology updates, AI products, infrastructure, chips, security, space, robotics, and software or cloud stories.

### 娱乐体育

Strategy: 2 headlines requests + 5 search requests = 7 requests.

| # | Type | Query | max |
|---|---|---|---|
| 1 | headlines | `category=entertainment` | 10 |
| 2 | headlines | `category=sports` | 10 |
| 3 | search | `celebrity OR star OR gossip` | 10 |
| 4 | search | `movie OR film OR box office` | 10 |
| 5 | search | `football OR soccer` | 10 |
| 6 | search | `basketball OR NBA` | 10 |
| 7 | search | `tennis OR golf OR Olympics OR racing` | 10 |
| backup | search | `video game OR e-sports OR streaming` | 10 |

Gossip, celebrity news, and entertainment rumors are allowed when sourced. Reject pure fabrication, harassment, or no-source paparazzi content.

### 旅游

Strategy: search only. GNews has no travel headlines category.

| # | Type | Query | max |
|---|---|---|---|
| 1 | search | `solo travel OR backpacking` | 10 |
| 2 | search | `airport OR flight delay OR airline` | 10 |
| 3 | search | `hotel OR resort OR accommodation` | 10 |
| 4 | search | `tourist destination OR travel guide` | 10 |
| 5 | search | `budget travel OR luxury travel` | 10 |
| 6 | search | `digital nomad OR remote work travel` | 10 |
| 7 | search | `cruise ship OR travel deal` | 10 |
| 8 | search | `national park OR adventure travel` | 10 |
| backup | search | `visa OR passport OR travel policy` | 10 |

Prefer route changes, airline updates, travel policy, destination trends, hotel or resort news, and practical travel information.

### 美食

Strategy: search only. GNews has no food headlines category.

| # | Type | Query | max |
|---|---|---|---|
| 1 | search | `fine dining OR restaurant review` | 10 |
| 2 | search | `street food OR local cuisine` | 10 |
| 3 | search | `michelin star OR food award` | 10 |
| 4 | search | `coffee shop OR bakery OR cafe` | 10 |
| 5 | search | `food trend OR healthy diet` | 10 |
| 6 | search | `wine tasting OR craft beer` | 10 |
| 7 | search | `cooking class OR food recipe` | 10 |
| 8 | search | `food festival OR food market` | 10 |
| backup | search | `dessert OR vegan food OR organic` | 10 |

Prefer dining news, restaurant openings, food trends, local cuisine, awards, markets, festivals, and practical food stories.

### 音乐

Strategy: search only. GNews has no dedicated music headlines category.

| # | Type | Query | max |
|---|---|---|---|
| 1 | search | `music OR musician OR singer` | 10 |
| 2 | search | `concert OR tour OR live performance` | 10 |
| 3 | search | `album OR single OR EP` | 10 |
| 4 | search | `billboard OR chart OR streaming` | 10 |
| 5 | search | `grammy OR music award` | 10 |
| 6 | search | `festival OR headline set OR lineup` | 10 |
| 7 | search | `band OR orchestra OR composer` | 10 |
| 8 | search | `music industry OR record label` | 10 |
| backup | search | `soundtrack OR score OR music release` | 10 |

Prefer artist releases, tours, live performances, charts, awards, festival lineups, and music industry developments.

### 生活

Strategy: search only. This category is for daily living, wellness, family life, work strain relief, and practical household knowledge.

| # | Type | Query | max |
|---|---|---|---|
| 1 | search | `healthy living OR wellness` | 10 |
| 2 | search | `superfood OR budget meal OR nutrition` | 10 |
| 3 | search | `sleep OR stress relief OR mental resilience` | 10 |
| 4 | search | `home remedy OR chronic disease advice` | 10 |
| 5 | search | `workplace injury OR back pain OR stretching` | 10 |
| 6 | search | `family life hack OR home cleaning OR household tips` | 10 |
| 7 | search | `healthy habit OR daily routine OR self care` | 10 |
| 8 | search | `consumer health warning OR health scam OR family safety` | 10 |
| backup | search | `wellness OR family health OR sleep routine` | 10 |

Prefer practical wellness guidance, low-cost nutrition, sleep and stress content, chronic disease education, work injury prevention, household life hacks, family safety, and health scam warnings.

## Keyword Guidelines

GNews search is not Google Search. Very narrow queries often return 0 results.

| Avoid | Prefer |
|---|---|
| `AI tools OR ChatGPT OR LLM launch` | `artificial intelligence OR AI startup` |
| `food trend OR restaurant opening` | `food OR restaurant OR cuisine` |
| `travel trend OR airline route OR tourism policy` | `travel OR tourism OR airline` |

Rules:

- Use moderately broad natural phrases.
- Combine 2-4 terms with `OR`.
- Avoid 5+ terms in one query.
- Avoid very specific product names as standalone terms.
- Test new keywords with `max=1` before using them in the weekly run.

## Scoring

Score total = relevance + novelty + completeness.

- Relevance: 0-10
- Novelty: 0-10
- Completeness: 0-10

Adaptive thresholds:

| Category | Threshold | Reason |
|---|---:|---|
| 科技AI | 20 | Dedicated headlines plus high-density search |
| 娱乐体育 | 20 | Dedicated headlines plus high-density search |
| 旅游 | 18 | Search only, no headlines category |
| 美食 | 18 | Search only, no headlines category |
| 音乐 | 18 | Search only, no headlines category |
| 生活 | 18 | Search only, practical daily living and wellness content |

Sort passed items by total score descending and select the top 25 per category.

## Source Blacklist

Always reject:

- `TMZ`
- Sources whose `source.name` contains `Crypto`, `Bet`, `Gambling`, `Casino`, `Forex`, `DraftKings`, or `Polymarket`

Newsweek, Fox News, and Daily Mail are not hard-blacklisted. Use the score and relevance checks unless the user changes the policy.
