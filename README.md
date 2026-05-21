# NewsCatch

Automated international news pipeline that fetches, filters, scores, and publishes curated content to Feishu (Lark) Base.

## Overview

NewsCatch pulls news from GNews API, filters articles from the past 7 days, scores them by relevance/novelty/completeness, generates English publication drafts with image prompts, and writes everything to a configured Lark Base table.

**Weekly output**: 100 articles (25 per category)

## Categories

| Category | Description |
|----------|-------------|
| 科技AI | Technology & AI |
| 娱乐体育 | Entertainment & Sports |
| 旅游 | Travel |
| 美食 | Food & Dining |

## Workflow

1. **Fetch** — Query GNews API (31 requests/week, 310 candidates, staggered round-robin to avoid 429)
2. **Pre-filter** — Remove duplicates, clickbait, expired articles, blacklisted sources
3. **Score** — Rate each article: relevance (0-10) + novelty (0-10) + completeness (0-10)
4. **Select** — Keep top 25 per category (**adaptive threshold**: 科技AI/娱乐体育 >= 20; 旅游/美食 >= 18)
5. **Generate** — English title, English body (600-1000 chars), image prompt (16:9)
6. **Publish** — Write records to Lark Base via `lark-cli`

## Scoring Threshold (Adaptive)

| Category | Score Required |
|----------|--------------|
| 科技AI | 20+ |
| 娱乐体育 | 20+ |
| 旅游 | 18+ (lower — no headlines category) |
| 美食 | 18+ (lower — no headlines category) |

## API Rate Limits

- GNews free tier: 100 requests/day
- **8-10 second delay between requests** (increased from 6s to reduce 429)
- **Round-robin stagger**: alternate requests across categories, not batch by category
- HTTP 429 triggers 30s wait + 1 retry; if 429 again, skip and move to next

## Source Blacklist

Excluded sources: TMZ, Crypto/Bet/Gambling/Casino/Forex-related sources.

## Quick Start

```powershell
# Configure GNews credentials for this shell
$env:GNEWS_API_KEY = "your-gnews-api-key"

# Check the request plan without consuming GNews quota
.\scripts\fetch-gnews.ps1 -DryRun

# Fetch, score, generate records, and build a Lark dry-run payload
.\scripts\run_pipeline.ps1

# Publish to Lark Base after checking records.normalized.json
.\scripts\run_pipeline.ps1 -Publish

# Or write an existing normalized file only
.\scripts\write_lark_records.ps1 -InputJson .\records.normalized.json
```

## Configuration

Target Lark Base:
- Base Token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table ID: `tblIDJ3Nv9Q2roXL`

GNews API Key: set `GNEWS_API_KEY` or pass `-ApiKey` to `scripts/fetch-gnews.ps1`.

## Project Structure

```
├── agents/           # Agent configurations
├── references/       # Category rules & guidelines
├── scripts/          # Automation scripts (PowerShell)
├── SKILL.md          # Full skill documentation
└── LICENSE
```

## Notes

- Only news within 7 days is considered valid
- Backup search (1 extra request per category) triggers when fewer than 25 articles pass scoring
- NewsCatch search queries use moderately broad phrases — very specific terms return 0 results
- **Optimization (2026-05-21)**: 旅游/美食 increased from 5→8 requests; adaptive scoring threshold (18 vs 20); round-robin request staggering to avoid 429
- `run_pipeline.ps1` publishes only when `-Publish` is provided; otherwise it creates a dry-run Lark payload.
