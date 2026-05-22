---
name: gnews-to-lark-base
description: "Use when the user wants to fetch international news with GNews API, filter and score the previous 7 days of articles, use the model to rewrite selected items into publishable English headlines, bodies, and image prompts, generate images, convert them to WebP, and write finished records into the configured Feishu/Lark Base table."
---

# GNews To Lark Base

Use this skill for the NewsCatch pipeline:

GNews fetch -> deterministic filtering and scoring -> model-written publication copy -> image generation -> local WebP conversion -> Feishu/Lark Base record creation -> Feishu attachment upload.

Important boundary: scripts do **not** write the final optimized title or body. The model must generate `generatedTitle`, `body`, and `imagePrompt` from the selected source material. Scripts handle repeatable plumbing.

## Defaults

- GNews key: use `GNEWS_API_KEY` or pass `-ApiKey`
- Lark CLI: use `lark-cli` on `PATH` or set `LARK_CLI`
- Image API URL: use `IMAGE_API_URL`
- Image API key: use `IMAGE_API_KEY`
- Image model: use `IMAGE_MODEL`, default `gpt-image-2`
- Image size: use `IMAGE_SIZE`, default `1792x1024`
- Image output format: use `IMAGE_OUTPUT_FORMAT`, default `webp`
- Python runtime for WebP conversion: use `PYTHON_EXE` or ensure `python` is available
- Base token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table id: `tblIDJ3Nv9Q2roXL`
- View id: `vewwG9FgZu`

## First-Time Setup

Before running:

1. Install [larksuite/cli](https://github.com/larksuite/cli), log in, and make sure your account can write to the target Base.
2. Get a GNews API key.
3. Prepare an image API that accepts prompt-based image generation.
4. Make sure Python with Pillow WebP support is available if you want `webp` output.

Then run:

```powershell
.\scripts\setup.ps1
```

## Normal Workflow

1. Fetch and pre-filter source articles:

```powershell
.\scripts\run_pipeline.ps1
```

This creates:

- `processed/filtered_articles.json`
- `processed/generation-input.json`
- `processed/fetch-summary.json`
- `processed/score-summary.json`

2. Use the model to create `records.normalized.json` from `processed/generation-input.json`.

Read `references/base-schema.md` first. For each selected item:

- write a rewritten English `generatedTitle`
- write a formal English `body`
- write an editorial `imagePrompt`
- set `generatedBy` to exactly `model`

3. Dry-run image generation and payload creation:

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords
```

This step:

- calls the configured image API
- accepts `data[0].url` or `data[0].b64_json`
- when `b64_json` is returned, saves a local image file
- converts it to WebP by default
- writes `processed/records.with-images.json`
- writes `processed/image-generation-summary.json`
- writes `lark-batch-create.json`

4. Publish only after review:

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish
```

This step creates the records and uploads the generated local image files to the Feishu attachment field `图片`.

## Script Responsibilities

- `scripts/setup.ps1`: environment setup and local config persistence
- `scripts/fetch-gnews.ps1`: GNews API calls, dedupe, blacklist, and filtered output
- `scripts/score-and-select.ps1`: deterministic scoring and top selection
- `scripts/generate_image_urls.ps1`: image API calls, `b64_json` decode, and optional PNG -> WebP conversion
- `scripts/write_lark_records.ps1`: validate records, create Base rows, and upload attachment files
- `scripts/run_pipeline.ps1`: orchestrate fetch/select and image/write stages

## Model Generation Rules

For each item in `processed/generation-input.json`:

- Use `sourceTitle`, `sourceDescription`, `sourceBody`, `sourceName`, `publishedAt`, and `sourceUrl`
- Preserve factual accuracy
- Do not invent facts, quotes, numbers, dates, places, or outcomes
- Rewrite the headline from scratch
- Write a standalone formal English news article
- Keep body length between 700 and 900 words, approximately 3,500-5,000 characters
- Generate an editorial image prompt with no text, no watermark, and no logo

## Feishu Write Rules

`write_lark_records.ps1` rejects records when:

- `generatedTitle`, `body`, or `imagePrompt` is missing
- `generatedBy` is missing or not exactly `model`
- `generatedTitle` is longer than 90 characters or appears truncated
- `body` is outside the accepted length range
- `body` starts like an internal summary
- `body` still contains source truncation markers
- `generatedImageUrl` is present but not a valid `http/https` URL

When a generated local image file exists in `generatedImagePath`, the writer uploads that file into Feishu field `图片` after the record is created.

## Notes

- Do not commit keys, tokens, or local machine paths to Git.
- Prefer environment variables over hard-coded values.
- Image generation may succeed even when no remote URL is returned. In that case, `generatedImagePath` becomes the important output.
- Do not claim that an image was attached unless the attachment upload step actually succeeded.
