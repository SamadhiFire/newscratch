# NewsScratch

NewsCatch is a Codex skill for collecting international news from GNews, selecting useful articles, using the model to rewrite them into publishable English copy, and writing the finished records to a Feishu/Lark Base table.

The important design point: scripts do not replace the model. They fetch, filter, score, select, validate, and write. Codex/the model rewrites the final title, body, and image prompt.

## Categories

| Category | Meaning |
|---|---|
| `科技AI` | Technology and AI |
| `娱乐体育` | Entertainment and sports |
| `旅游` | Travel |
| `美食` | Food and dining |

Weekly target: 25 articles per category, 100 total.

## First-Time Setup

Before running:

1. Install [larksuite/cli](https://github.com/larksuite/cli), log in, and make sure your account can write to the target Feishu/Lark Base.
2. Get a free GNews API key from [gnews.io](https://gnews.io/).

Then run:

```powershell
.\scripts\setup.ps1
```

The setup script can store `GNEWS_API_KEY` and `LARK_CLI` in your local user environment variables. They stay on your own computer and are not stored in this repository.

## Workflow

1. Fetch, filter, score, and select articles:

```powershell
.\scripts\run_pipeline.ps1
```

This creates `processed/generation-input.json`.

2. Ask Codex/the model to generate `records.normalized.json` from `processed/generation-input.json`.

The model must create:

- `generatedTitle`: concise rewritten English headline.
- `body`: formal English news article, 600-1000 characters.
- `imagePrompt`: 16:9 editorial image prompt.
- `generatedBy`: exactly `model`.

3. Build and inspect the Lark payload:

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords
```

4. Publish after review:

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish
```

## Why There Is A Script

The scripts handle deterministic work:

- GNews API request planning and rate limiting.
- 7-day time window.
- Duplicate/clickbait/blacklist filtering.
- Category scoring and top-25 selection.
- JSON contract shaping.
- Lark payload generation and upload.

The scripts should not invent publication copy. Titles and bodies need model judgment, so they are generated after `processed/generation-input.json` is ready.

## Configuration

Target Base:

- Base token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table id: `tblIDJ3Nv9Q2roXL`
- View id: `vewwG9FgZu`

GNews API key is not stored in the repo. Use `GNEWS_API_KEY` or pass `-ApiKey` to `scripts/fetch-gnews.ps1`.

## Files

```text
agents/                 Codex skill UI metadata
references/             Category rules and Base schema
scripts/                PowerShell automation scripts
SKILL.md                Skill instructions for Codex
README.md               Human-facing GitHub overview
LICENSE
```

Runtime output is ignored by Git:

- `processed/`
- `data/`
- `records.normalized.json`
- `lark-batch-create.json`

## Notes

- GNews free tier allows 100 requests/day.
- Default fetch uses 31 requests, plus up to 4 backup requests.
- Requests are staggered across categories with 8-10 seconds between calls to reduce 429 errors.
- `旅游` and `美食` have no GNews headline category, so they rely on broader search queries and a slightly lower score threshold.
