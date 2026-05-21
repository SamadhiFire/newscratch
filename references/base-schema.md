# Base Schema And Normalized Record Contract

## Target Feishu Base

- Base token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table id: `tblIDJ3Nv9Q2roXL`
- View id: `vewwG9FgZu`

## Writable Fields

| Field | Type | Notes |
|---|---|---|
| `新闻分类` | select | One of `科技AI`, `娱乐体育`, `旅游`, `美食` |
| `新闻来源链接` | URL text | Write URL string |
| `新闻标题` | text | Source or generated title |
| `新闻正文` | text | Original GNews `content` or `description`, kept for reference |
| `发布日期` | datetime | Prefer source publish time |
| `状态` | select | `已生成` or `失败` |
| `AI评分` | number | **Total score only** (e.g., `24`). Do NOT put text here. |
| `AI评价内容` | text | Detailed breakdown: per-dimension scores + reason. E.g. `"相关性8，新颖性8，完整度8。通过原因：..."` |
| `优化后标题` | text | Final generated title |
| `优化后正文` | text | Final generated English body, 600-1000 chars |
| `文生图提示词` | text | Image prompt |
| `发布状态` | select | Usually `未发布` |

Do not write `新闻ID` unless the user explicitly asks. Do not write read-only fields such as created/updated metadata.

## Normalized Input For Script

`scripts/write_lark_records.ps1` expects a JSON array:

```json
[
  {
    "category": "科技AI",
    "sourceUrl": "https://example.com/news/1",
    "sourceTitle": "source title",
    "sourceBody": "original GNews content or description",
    "publishedAt": "2026-05-20 09:30:00",
    "generatedTitle": "rewritten English headline",
    "body": "600-1000 character English publication draft",
    "imagePrompt": "16:9封面图提示词",
    "score": 24,
    "evaluation": "相关性8，新颖性8，完整度8。通过原因...",
    "status": "已生成",
    "publishStatus": "未发布"
  }
```

**Field mapping:**
- `score` → `AI评分` (must be a **plain integer**, e.g. `24`)
- `evaluation` → `AI评价内容` (full text with breakdown)

Minimum required fields: `category`, `sourceUrl`, `generatedTitle`, `body`, `imagePrompt`, `score`.

If `sourceBody` is missing, the write script falls back to `body` for `新闻正文`. If `publishedAt` is missing, use the run time. If `status` is missing, use `已生成`. If `publishStatus` is missing, use `未发布`.
