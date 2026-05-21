---
name: gnews-to-lark-base
description: "Use when the user wants to fetch international news with GNews API, filter and score the previous 7 days of articles, use the model to rewrite selected items into publishable English headlines/bodies/image prompts, and write finished records into the configured Feishu/Lark Base table with lark-cli. Weekly target is 25 articles per category, 100 total."
---

# GNews To Lark Base

Use this skill for the NewsCatch pipeline: GNews fetch -> deterministic filtering/scoring -> model-written publication copy -> Feishu/Lark Base write.

Important boundary: scripts do **not** write the final optimized title/body. The model must generate `generatedTitle`, `body`, and `imagePrompt` from the selected source material. Scripts only handle repeatable plumbing: API calls, rate limits, filtering, scoring, JSON shaping, and Lark writes.

## Defaults

- GNews key: never store it in this repo. Use `GNEWS_API_KEY` or pass `-ApiKey`.
- Lark CLI: use `lark-cli` on `PATH` or set `LARK_CLI`.
- Base token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table id: `tblIDJ3Nv9Q2roXL`
- View id: `vewwG9FgZu`
- Categories: `科技AI`, `娱乐体育`, `旅游`, `美食`
- Weekly target: 25 articles per category, 100 total

## First-Time Setup

Before running the pipeline, confirm the user has:

1. Installed [larksuite/cli](https://github.com/larksuite/cli), logged in, and obtained write access to the target Base.
2. Created a free GNews API key at [gnews.io](https://gnews.io/).

Then run:

```powershell
.\scripts\setup.ps1
```

The setup helper can save `GNEWS_API_KEY` and `LARK_CLI` to the user's local environment variables. Those values stay on that machine and are not committed to GitHub.

## Normal Workflow

1. Fetch and pre-filter GNews articles:

```powershell
.\scripts\run_pipeline.ps1
```

This creates:

- `processed/raw_gnews.json`
- `processed/filtered_articles.json`
- `processed/generation-input.json`
- `processed/fetch-summary.json`
- `processed/score-summary.json`

2. Use the model to create `records.normalized.json` from `processed/generation-input.json`.

Read `references/base-schema.md` before generating the normalized output. For every selected item, preserve source facts and create these fields:

- `generatedTitle`: rewritten English headline, 45-90 characters, complete and not truncated.
- `body`: formal English news article, 700-900 words (approximately 3,500–5,000 characters), readable as a standalone article with sufficient depth, context, and detail.
- `imagePrompt`: 16:9 editorial cover prompt, no text, no watermark, no logo.
- `generatedBy`: exactly `model`, so the writer can reject old script/template artifacts.

Do not publish template prose. Do not start bodies with `A report from`, `According to the source`, or `This story fits`. The article should read like a formal news article for readers, not like an internal summary of GNews metadata.

3. Dry-run the Lark payload:

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords
```

4. Publish only after reviewing `records.normalized.json` and `lark-batch-create.json`:

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish
```

You can also call the writer directly:

```powershell
.\scripts\write_lark_records.ps1 -InputJson .\records.normalized.json -DryRun
.\scripts\write_lark_records.ps1 -InputJson .\records.normalized.json
```

## Script Responsibilities

- `scripts/setup.ps1`: first-time environment setup and dry-run plan check.
- `scripts/fetch-gnews.ps1`: GNews API calls, 7-day window, round-robin category staggering, retry handling, dedupe, blacklist, and filtered output.
- `scripts/score-and-select.ps1`: deterministic scoring and top-25 selection. It outputs `processed/generation-input.json` for the model.
- `scripts/score-and-generate.ps1`: deprecated compatibility wrapper. It does not generate final copy.
- `scripts/write_lark_records.ps1`: validates `records.normalized.json`, builds Lark batch payload, and writes to Base.
- `scripts/run_pipeline.ps1`: orchestrates fetch/select, or writes an already generated records file when `-WriteExistingRecords` is set.

## Request Strategy

Read `references/category-rules.md` before changing keywords or thresholds.

- Time window: previous 7 days.
- Free tier: 100 GNews requests/day, max 10 articles/request.
- Default run: 31 requests plus up to 4 backup requests.
- Use round-robin category staggering and wait 8-10 seconds between requests.
- On HTTP 429: wait 30 seconds, retry once, then skip that request and record the failure.
- Include backup searches by default; use `-SkipBackup` only to save quota.

## Filtering And Scoring

Quick pre-filter removes:

- Empty, generic, or clickbait titles.
- Descriptions shorter than 50 characters.
- Duplicate URLs or near-duplicate titles.
- Sources older than 7 days.
- Blacklisted sources: `TMZ`, and sources containing `Crypto`, `Bet`, `Gambling`, `Casino`, `Forex`, `DraftKings`, or `Polymarket`.

Scoring uses:

- Relevance: 0-10
- Novelty: 0-10
- Completeness: 0-10

Adaptive pass thresholds:

- `科技AI`: >= 20
- `娱乐体育`: >= 20
- `旅游`: >= 18
- `美食`: >= 18

Select the top 25 passed items per category. If fewer than 25 pass, run one backup search for that category and note any remaining shortfall.

## Model Generation Rules

For each item in `processed/generation-input.json`:

- Use `sourceTitle`, `sourceDescription`, `sourceBody`, `sourceName`, `publishedAt`, and `sourceUrl`.
- Strip and ignore any GNews `[+N chars]` suffix.
- Preserve factual accuracy. Do not invent quotes, numbers, locations, names, or outcomes that are not supported by the source fields.
- You may add light category context only when it is generic and does not introduce new facts.
- Rewrite the headline from scratch. Do not copy the GNews title unless the source title is already a clean publication headline and still needs no improvement.
- Write a standalone formal English news article, not a bullet summary or source attribution sentence.
- Keep body length between 700 and 900 words (approximately 3,500–5,000 characters).
- Generate an editorial image prompt that describes the visual scene; no text/watermarks/logos.

Output must be a JSON array matching `references/base-schema.md`.

## Lark Write Rules

`write_lark_records.ps1` rejects records when:

- `generatedTitle`, `body`, or `imagePrompt` is missing.
- `generatedBy` is missing or is not exactly `model`.
- `generatedTitle` is longer than 90 characters or appears truncated.
- `body` is outside 700-900 words (approximately 3,500–5,000 characters).
- `body` starts like an internal summary (`A report from`, `According to the source`, `This story fits`).
- `body` still contains a GNews truncation suffix.

If `lark-cli` hits sandbox/keychain restrictions, rerun that command with approval/escalation.

## Output Summary

For each run, report:

- API request count and any 429/skipped requests.
- Candidates fetched per category.
- Items kept after pre-filter.
- Items passed scoring.
- Items selected for model generation.
- Records generated by the model.
- Records dry-run or written to Feishu.
- Category shortfalls and any permission/API failures.

Do not claim image files are attached unless an image generation and upload step actually ran.
