# NewsCatch

Automated international news pipeline that fetches, filters, scores, and publishes curated content to Feishu (Lark) Base.

## Overview

NewsCatch pulls news from GNews API, filters articles from the past 7 days, scores them by relevance/novelty/completeness, generates Chinese summaries with image prompts, and writes everything to a configured Lark Base table.

**Weekly output**: 100 articles (25 per category)

## Categories

| Category | Description |
|----------|-------------|
| 科技AI | Technology & AI |
| 娱乐体育 | Entertainment & Sports |
| 旅游 | Travel |
| 美食 | Food & Dining |

## Workflow

1. **Fetch** — Query GNews API (25 requests/week, 250 candidates)
2. **Pre-filter** — Remove duplicates, clickbait, expired articles, blacklisted sources
3. **Score** — Rate each article: relevance (0-10) + novelty (0-10) + completeness (0-10)
4. **Select** — Keep top 25 per category (score >= 20 required)
5. **Generate** — English title, English body (600-800 chars), image prompt (16:9)
6. **Publish** — Write records to Lark Base via `lark-cli`

## Scoring Threshold

| Score Range | Action |
|-------------|--------|
| 20+ | Accepted |
| < 20 | Rejected |

## API Rate Limits

- GNews free tier: 100 requests/day
- 6-second delay between requests
- HTTP 429 triggers 30s wait + 1 retry

## Source Blacklist

Excluded sources: TMZ, Crypto/Bet/Gambling/Casino/Forex-related sources.

## Quick Start

```powershell
# Install dependencies
npm install

# Configure Lark credentials
lark-cli auth login

# Run the pipeline
.\scripts\write_lark_records.ps1 -InputJson .\records.normalized.json
```

## Configuration

Target Lark Base:
- Base Token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table ID: `tblIDJ3Nv9Q2roXL`

GNews API Key: `ebc3f32f8ed3f49c5a25ac145cb55ed7`

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
