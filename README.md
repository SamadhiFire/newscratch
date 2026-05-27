# Spaceplayax Content Batch Builder

这个仓库现在的主目标不是写飞书，而是生成 Spaceplayax 内容包：

```text
spaceplayax-content-batch-YYYY-MM-DD.zip
```

zip 解压后必须只有一个顶层目录：

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

## 核心思路

不要让 Skill 手工控制复杂流程。Skill 只负责调用本地批处理工具，真正的结构生成、生图、WebP 转换、zip 打包和校验都由脚本完成。

跨平台建议：

- Windows 和 macOS 都统一使用 PowerShell 7，也就是 `pwsh`
- Python 需要带 Pillow，并且 Pillow 必须支持 WebP
- mac 上如果没有 `python`，脚本会自动尝试 `python3`

主脚本：

```powershell
pwsh -File ./scripts/build_spaceplayax_batch.ps1
```

## 推荐运行方式

准备好文章 JSON 后运行：

```powershell
pwsh -File ./scripts/build_spaceplayax_batch.ps1 -InputJson ./records.normalized.json -Date 2026-05-26 -Workers 3 -Resume
```

如果你在 Windows PowerShell 里直接跑 `.\scripts\build_spaceplayax_batch.ps1` 也可以，但为了兼容 mac，文档默认都用 `pwsh -File`。

输出位置：

```text
dist/
  spaceplayax-content-batch-2026-05-26/
  spaceplayax-content-batch-2026-05-26.zip
```

## 输入 JSON

脚本接受一个 JSON 数组。可以使用旧流程生成的 `records.normalized.json`，也可以使用你自己的 `articles.json`。

每篇文章建议包含：

```json
{
  "generatedTitle": "Article title",
  "body": "Article body or Markdown content",
  "imagePrompt": "Prompt for one cover image, no text, no watermark, no logo.",
  "category": "科技AI",
  "sourceUrl": "https://example.com/source",
  "sourceTitle": "Original source title",
  "sourceName": "Source name",
  "publishedAt": "2026-05-26 10:00:00"
}
```

也支持这些替代字段：

- `title` 可替代 `generatedTitle`
- `articleMarkdown` 或 `bodyMarkdown` 可替代 `body`
- `slug` 可手动指定；缺失时脚本会自动生成

## 环境变量

不要把 key 写进仓库。用环境变量或运行参数传入。

图片生成需要：

```powershell
$env:IMAGE_API_URL = "https://newapi.860812.xyz/v1/images/generations"
$env:IMAGE_API_KEY = "..."
$env:IMAGE_MODEL = "gpt-image-2"
$env:IMAGE_SIZE = "1152x576"
$env:PYTHON_EXE = "C:\path\to\python.exe"
# mac 示例：
# $env:PYTHON_EXE = "/opt/homebrew/bin/python3"
```

如果 `python3` 已经在 PATH 里，`PYTHON_EXE` 也可以不填。

如果还需要上游自动生文，可以配置：

```powershell
$env:TEXT_API_BASE = "https://newapi.860812.xyz"
$env:TEXT_API_KEY = "..."
$env:TEXT_MODEL = "gpt-5.4-mini"
```

## 100 篇一天怎么跑

本地机器只是调 API、写文件、转 WebP、打 zip，真正耗时的是图片 API。

建议：

```powershell
pwsh -File ./scripts/build_spaceplayax_batch.ps1 -InputJson ./articles.json -Date 2026-05-26 -Workers 3 -Resume
```

原则：

- 先用 `-Workers 3`
- 接口稳定后再试 `-Workers 5`
- 长任务一定带 `-Resume`
- 已经存在且有效的 `cover.webp` 会跳过
- 中途断网后重新运行同一条命令即可续跑

## 校验规则

脚本会校验：

- zip 文件名符合 `spaceplayax-content-batch-YYYY-MM-DD.zip`
- zip 内只有一个顶层目录
- 每篇文章位于 `posts/YYYY-MM-DD-slug/`
- 每篇文章有 `manifest.json`
- 每篇文章有 `article.md`
- 每篇文章有 `images/cover.webp`
- `cover.webp` 是真实 WebP 文件
- `batch-manifest.json` 记录本批次文章

如果校验失败，脚本不会产出成功结果。查看：

```text
dist/spaceplayax-content-batch-YYYY-MM-DD-build-summary.json
```

然后修复问题并使用 `-Resume` 继续。

## 旧脚本说明

这些旧脚本还可以作为“准备文章输入”的工具：

- `scripts/fetch-gnews.ps1`
- `scripts/score-and-select.ps1`
- `scripts/generate_records_newapi.ps1`
- `scripts/merge_generated_records.ps1`

这些是旧飞书流程，不再是主路径：

- `scripts/write_lark_records.ps1`
- `scripts/run_pipeline.ps1 -WriteExistingRecords -Publish`

## 不要提交

- API key
- 本地生成图片
- `dist/`
- `processed/`
- `records.normalized.json`
- zip 产物
