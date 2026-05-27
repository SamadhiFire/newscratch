---
name: spaceplayax-content-batch
description: "Use when the user wants to build a Spaceplayax content batch zip containing multiple Markdown articles, regenerated WebP cover images, per-post manifests, and a batch manifest. The skill should call the local batch builder instead of publishing to Feishu/Lark."
---

# Spaceplayax Content Batch

Use this skill when the user wants a local content package named:

```text
spaceplayax-content-batch-YYYY-MM-DD.zip
```

The output zip must contain exactly one top-level directory:

```text
spaceplayax-content-batch-YYYY-MM-DD/
  batch-manifest.json
  posts/
    YYYY-MM-DD-slug/
      manifest.json
      article.md
      images/
        cover.webp
```

## Core Boundary

This is no longer a Feishu/Lark publishing workflow.

The model may generate article text, metadata, and image prompts through a configured text API, but the final directory layout, image files, manifests, zip creation, and validation must be handled by local deterministic tooling.

Do not manually create images one by one. Use the local batch builder so the run can resume, retry failed image requests, and validate the package.

For cross-platform use, prefer PowerShell 7 via `pwsh -File ...`. Do not assume Windows-only path separators or the `py` launcher exists.

## Main Command

Build a batch from an article JSON file:

```powershell
pwsh -File ./scripts/build_spaceplayax_batch.ps1 -InputJson ./records.normalized.json -Date 2026-05-26 -Workers 3 -Resume
```

The builder will:

- Create `dist/spaceplayax-content-batch-YYYY-MM-DD/`
- Create one `posts/YYYY-MM-DD-slug/` folder per article
- Write each `article.md` without frontmatter
- Write each per-post `manifest.json`
- Regenerate one `images/cover.webp` per article
- Write `batch-manifest.json`
- Create `dist/spaceplayax-content-batch-YYYY-MM-DD.zip`
- Validate that the zip has exactly one top-level directory

## Inputs

The builder accepts a JSON array. It works with `records.normalized.json` produced by the legacy scripts, or an equivalent `articles.json`.

Recommended fields per article:

- `generatedTitle` or `title`
- `body`, `bodyMarkdown`, or `articleMarkdown`
- `imagePrompt`
- `category`
- `sourceUrl`
- `sourceTitle`
- `sourceName`
- `publishedAt`
- `slug` optional; when missing, the builder creates one

## Environment

Do not commit keys or local paths. Configure secrets via environment variables or pass parameters at runtime.

Required for image generation:

- `IMAGE_API_URL`, for example `https://newapi.860812.xyz/v1/images/generations`
- `IMAGE_API_KEY`
- `IMAGE_MODEL`, default `gpt-image-2`
- `IMAGE_SIZE`, default `1152x576`
- `PYTHON_EXE` pointing to Python with Pillow WebP support, or make `python3`/`python` available on `PATH`

Optional for upstream text/article generation:

- `TEXT_API_BASE`, for example `https://newapi.860812.xyz`
- `TEXT_API_KEY`
- `TEXT_MODEL`, for example `gpt-5.4-mini`

## Scaling Rules

For about 100 articles per day:

- Start with `-Workers 3`
- Increase to `-Workers 5` only if the image API is stable
- Always use `-Resume` for long runs
- Keep generated files on disk; reruns skip existing valid `cover.webp` files
- Treat image failures as batch failures unless the user explicitly asks for a partial batch

The local machine is not doing the heavy image computation. It is coordinating API calls, saving files, converting to WebP, and building the zip. The practical limits are image API speed, rate limits, network stability, and cost.

## Validation Requirements

Before reporting success, verify:

- The zip filename is `spaceplayax-content-batch-YYYY-MM-DD.zip`
- The zip has exactly one top-level directory
- Every post is under `posts/YYYY-MM-DD-slug/`
- Every post contains `manifest.json`
- Every post contains `article.md`
- Every post contains `images/cover.webp`
- Every cover file is valid WebP
- `article.md` has no frontmatter
- `batch-manifest.json` lists the included posts

`build_spaceplayax_batch.ps1` performs these checks and fails before zipping when files are missing or invalid.

## Legacy Scripts

Some older NewsCatch scripts are still useful for preparing article input:

- `scripts/fetch-gnews.ps1`
- `scripts/score-and-select.ps1`
- `scripts/generate_records_newapi.ps1`
- `scripts/merge_generated_records.ps1`

Do not use the legacy Feishu writer as the main path for Spaceplayax batches:

- `scripts/write_lark_records.ps1`
- `scripts/run_pipeline.ps1 -WriteExistingRecords -Publish`

## Failure Handling

If a run fails:

1. Check `dist/spaceplayax-content-batch-YYYY-MM-DD-build-summary.json`
2. Fix environment, API, or content issues
3. Rerun the same command with `-Resume`

Do not delete the partially built batch directory unless the user explicitly wants a clean rebuild.
