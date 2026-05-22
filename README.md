# NewsCatch

NewsCatch is a Codex skill and script bundle for collecting international news from GNews, selecting useful articles, using the model to rewrite them into publishable English copy, generating cover images, converting those images to WebP, and writing finished records into a Feishu/Lark Base table.

The important design point: scripts do not replace the model. They fetch, filter, score, select, call the image API, convert image files, build payloads, and upload to Feishu. Codex or another model rewrites the final title, body, and image prompt.

## Categories

| Category | Meaning |
|---|---|
| `科技AI` | Technology and AI |
| `娱乐体育` | Entertainment and sports |
| `旅游` | Travel |
| `美食` | Food and dining |
| `音乐` | Music |

Weekly target: 25 articles per category, 125 total.

## First-Time Setup

Before running:

1. Install [larksuite/cli](https://github.com/larksuite/cli), log in, and make sure your account can write to the target Feishu/Lark Base.
2. Get a GNews API key from [gnews.io](https://gnews.io/).
3. Prepare an image API that can generate images from prompts.
4. Make sure Python is available for WebP conversion. The repository expects Pillow with WebP support.

Then run:

```powershell
.\scripts\setup.ps1
```

The setup helper can store local environment variables for you. Those values stay on your own machine and must not be committed to Git.

## Environment Variables

You can configure the pipeline entirely through environment variables:

```powershell
$env:GNEWS_API_KEY = "..."
$env:LARK_CLI = "C:\path\to\lark-cli.ps1"
$env:IMAGE_API_URL = "http://host:port/v1/images/generations"
$env:IMAGE_API_KEY = "..."
$env:IMAGE_MODEL = "gpt-image-2"
$env:IMAGE_SIZE = "1792x1024"
$env:IMAGE_OUTPUT_FORMAT = "webp"
$env:PYTHON_EXE = "C:\path\to\python.exe"
```

Recommended defaults for the tested internal setup:

- `IMAGE_MODEL=gpt-image-2`
- `IMAGE_SIZE=1792x1024`
- `IMAGE_OUTPUT_FORMAT=webp`

## Workflow

1. Fetch, filter, score, and select source articles:

```powershell
.\scripts\run_pipeline.ps1
```

This creates `processed/generation-input.json`.

2. Ask Codex or another model to generate `records.normalized.json` from `processed/generation-input.json`.

Each record should include:

- `generatedTitle`
- `body`
- `imagePrompt`
- `generatedBy` with exact value `model`

Optional fields such as `generatedImageUrl` and `generatedImagePath` will be filled by scripts later.

3. Dry-run image generation and Feishu payload creation:

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords
```

This step:

- calls the image API
- saves generated local files under `processed/generated-images/`
- converts images to WebP by default
- writes `processed/records.with-images.json`
- writes `processed/image-generation-summary.json`
- writes a preview payload to `lark-batch-create.json`

4. Publish after review:

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish
```

This step:

- creates Base records
- writes `生成图片` when a remote URL exists
- uploads the local generated image file into the Feishu attachment field `图片`

## Why There Is A Script

The scripts handle deterministic work:

- GNews API request planning and rate limiting
- 7-day time window
- duplicate, clickbait, and blacklist filtering
- category scoring and top-25 selection
- image API calls
- decoding `b64_json`
- PNG to WebP conversion
- Feishu payload generation
- Feishu record creation and attachment upload

The scripts should not invent publication copy. Titles and bodies still need model judgment.

## Image Pipeline

The tested image path is:

1. request image generation from `IMAGE_API_URL`
2. accept either `data[0].url` or `data[0].b64_json`
3. when `b64_json` is returned, save a local PNG
4. convert that PNG to WebP when `IMAGE_OUTPUT_FORMAT=webp`
5. create the Feishu record
6. upload the generated local file to attachment field `图片`

If the image API returns only a remote URL, the URL can still be written to `生成图片`.

## Target Base

- Base token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table id: `tblIDJ3Nv9Q2roXL`
- View id: `vewwG9FgZu`

See [references/base-schema.md](C:\Users\AS\Desktop\newscatch\references\base-schema.md) for the normalized record contract and field mapping.

## Files

```text
agents/                 Codex skill UI metadata
references/             Category rules and Base schema
scripts/                PowerShell automation scripts
SKILL.md                Skill instructions for Codex
README.md               Human-facing overview
LICENSE
```

Runtime output is ignored by Git:

- `processed/`
- `data/`
- `records.normalized.json`
- `lark-batch-create.json`

## Notes

- GNews free tier allows 100 requests/day.
- Default fetch uses 43 requests including 5 backup requests.
- Requests are staggered across categories with 8-10 seconds between calls to reduce 429 errors.
- `旅游`, `美食`, and `音乐` rely on broader search queries and a slightly lower score threshold.
- If image generation fails for a record, the record can still be written with an empty `生成图片` field and `状态=失败`.
- If attachment upload fails after record creation, the record remains in Base and the upload step should be retried with the same local file.
