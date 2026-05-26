# NewsScatch 新闻采集与飞书发布 Skill

这是一个用于新闻采集、筛选、改写、配图并写入飞书多维表格的 Skill 与脚本集合。

当前已经打通的完整链路是：

`GNews 抓取 -> 筛选与评分 -> 模型生成标题/正文/图片提示词 -> 图片接口生成图片 -> 本地转 WebP -> 写入飞书记录 -> 上传飞书图片附件`

这个仓库的设计原则是：

- 脚本负责可重复、确定性的工作
- 模型负责最终内容生成
- 不把密钥、内网地址、个人环境路径写死进仓库

## 这个仓库能做什么

这套流程可以完成以下工作：

1. 从 GNews 拉取最近 7 天的国际新闻
2. 按分类进行筛选、去重、评分
3. 生成供模型改写的 `generation-input.json`
4. 由模型生成：
   - 英文标题
   - 英文正文
   - 图片提示词
5. 调用图片接口生成封面图
6. 将图片转成 `webp`
7. 写入飞书多维表格
8. 把生成好的图片作为附件上传到飞书字段 `图片`

## 支持的新闻分类

| 分类 | 含义 |
|---|---|
| `科技AI` | 科技与 AI |
| `娱乐体育` | 娱乐与体育 |
| `旅游` | 旅游 |
| `美食` | 餐饮与美食 |
| `音乐` | 音乐 |
| `生活` | 生活方式与家庭日常 |

周目标默认是每个分类 25 条，共 150 条。

## 仓库结构

```text
agents/                 Codex Skill 配置
references/             规则、字段结构、说明文档
scripts/                主流程 PowerShell 脚本
README.md               项目说明
SKILL.md                给 Codex 用的技能说明
LICENSE
```

## 运行前必须准备的内容

别人拿到这个仓库后，至少要自己准备下面几项：

### 1. GNews API Key

这个仓库不会自带 GNews Key。

你需要自己去申请，然后配置：

```powershell
$env:GNEWS_API_KEY = "你的 GNews API Key"
```

### 2. 飞书 CLI

需要安装并登录 [larksuite/cli](https://github.com/larksuite/cli)。

你必须保证：

- 本机能运行 `lark-cli`
- 已经完成登录
- 当前登录身份对目标飞书多维表格有写权限

如果不是默认 PATH，也可以手动指定：

```powershell
$env:LARK_CLI = "C:\path\to\lark-cli.ps1"
```

### 3. 图片生成 API

这个仓库不会内置图片 API Key，也不会假设所有人都用同一个图片网关。

你至少需要自己配置：

```powershell
$env:TEXT_API_BASE = "https://newapi.860812.xyz"
$env:TEXT_API_KEY = "你的 newapi Key"
$env:TEXT_MODEL = "gpt-5.4-mini"
$env:IMAGE_API_URL = "https://newapi.860812.xyz/v1/images/generations"
$env:IMAGE_API_KEY = "你的 newapi Key"
$env:IMAGE_MODEL = "gpt-image-2"
$env:IMAGE_SIZE = "1152x576"
```

### 4. Python 与 Pillow

当前图片转 `webp` 的步骤依赖 Python + Pillow。

你需要保证本机：

- 能找到可用 Python
- Pillow 已安装
- Pillow 支持 WebP 编码

你也可以显式指定 Python：

```powershell
$env:PYTHON_EXE = "C:\path\to\python.exe"
```

### 5. WebP 输出格式

当前推荐默认输出：

```powershell
$env:IMAGE_OUTPUT_FORMAT = "webp"
```

也支持改成：

```powershell
$env:IMAGE_OUTPUT_FORMAT = "png"
```

但如果你要上传到飞书并尽量减小体积，推荐继续使用 `webp`。

## 推荐环境变量配置

建议别人先把这些变量配齐：

```powershell
$env:GNEWS_API_KEY = "..."
$env:LARK_CLI = "C:\path\to\lark-cli.ps1"
$env:TEXT_API_BASE = "https://newapi.860812.xyz"
$env:TEXT_API_KEY = "..."
$env:TEXT_MODEL = "gpt-5.4-mini"
$env:IMAGE_API_URL = "https://newapi.860812.xyz/v1/images/generations"
$env:IMAGE_API_KEY = "..."
$env:IMAGE_MODEL = "gpt-image-2"
$env:IMAGE_SIZE = "1152x576"
$env:IMAGE_OUTPUT_FORMAT = "webp"
$env:PYTHON_EXE = "C:\path\to\python.exe"
```

如果希望持久化，可以运行：

```powershell
.\scripts\setup.ps1
```

如果 Windows 提示禁止运行脚本，可以只对当前命令使用临时绕过：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

## 私有网络运行时的注意事项

这部分非常重要，尤其是别人照抄仓库时很容易踩坑。

### 1. GitHub 不一定能直连

如果是在公司网络、办公网络或特定私有网络环境下：

- `github.com:443` 可能被拦截
- GitHub Desktop 可能无法 `Fetch` / `Push`
- 浏览器能打开 GitHub，并不代表 Git 一定能通

如果遇到：

```text
fatal: unable to access 'https://github.com/...': Failed to connect to github.com port 443
```

通常不是仓库问题，而是当前网络、代理、VPN 或公司出口策略问题。

### 2. 图片接口可能是私有接口

图片接口地址必须由运行者自己通过 `IMAGE_API_URL` 配置。不要把公司内网地址、个人代理地址或带凭证的地址提交到仓库。

### 3. 内网图片接口返回格式可能不是 URL

有些图片接口在成功时可能返回：

- `data[0].b64_json`

而不是：

- `data[0].url`

所以当前脚本已经专门做了兼容：

1. 如果返回 `url`，可直接记入 `生成图片`
2. 如果返回 `b64_json`，脚本会：
   - 先保存 PNG
   - 再转成 WebP
   - 再上传飞书 `图片` 字段

### 4. 图片接口生成成功，不代表会有远程 URL

这是一个非常容易误解的点。

当前流程里，以下情况也算图片成功：

- 图片接口返回了 `b64_json`
- 本地文件生成成功
- WebP 转换成功
- 飞书附件上传成功

即使这时候：

- `生成图片` 字段为空

也不代表失败，因为真正的图片已经在飞书 `图片` 附件字段里了。

### 5. WebP 转换必须有 Python 运行时

如果别人是在公司网络、Windows 机器、受控环境里运行，最容易缺的是：

- 没有 Python
- Pillow 没装
- Pillow 不支持 WebP

当前脚本会优先找：

- `PYTHON_EXE`
- 系统 `python`
- 系统 `py`
- Codex 桌面运行时自带 Python

如果都找不到，`webp` 步骤就会失败。

## 目标飞书多维表格

当前配置的目标表：

- Base token: `ZpWrbn0M9ajJn8s6qDycQhDWnsN`
- Table id: `tblIDJ3Nv9Q2roXL`
- View id: `vewwG9FgZu`

当前已经对齐的核心字段有：

- `新闻分类`
- `新闻来源链接`
- `新闻标题`
- `新闻正文`
- `发布日期`
- `状态`
- `AI评分`
- `AI评价内容`
- `优化后标题`
- `优化后正文`
- `文生图提示词`
- `生成图片`
- `发布状态`
- `图片`（附件字段）

详细字段契约见：

[references/base-schema.md](references/base-schema.md)

## 当前主流程

### 第一步：抓取与筛选新闻

```powershell
.\scripts\run_pipeline.ps1
```

这一步会生成：

- `processed/filtered_articles.json`
- `processed/generation-input.json`
- `processed/fetch-summary.json`
- `processed/score-summary.json`

### 第二步：让模型生成 `records.normalized.json`

默认情况下，确定性脚本不会用模板自动生成最终文章正文；最终内容必须由模型生成。

需要模型根据：

- `sourceTitle`
- `sourceDescription`
- `sourceBody`
- `publishedAt`
- `sourceUrl`

来生成：

- `generatedTitle`
- `body`
- `imagePrompt`
- `generatedBy = model`

如果已经配置 `TEXT_API_BASE` / `TEXT_API_KEY`，可以用 newapi 自动调用模型生成：

```powershell
.\scripts\generate_records_newapi.ps1
```

### 第三步：生成图片并 dry-run

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords
```

这一步会：

- 调图片接口
- 生成本地图片
- 转成 `webp`
- 写出 `processed/records.with-images.json`
- 写出 `processed/image-generation-summary.json`
- 写出 `lark-batch-create.json`

### 第四步：正式写入飞书

```powershell
.\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish
```

这一步会：

1. 创建飞书记录
2. 将 `生成图片` 字段写入 URL（如果有）
3. 将本地生成的 `webp` 上传到飞书附件字段 `图片`

## 关键脚本说明

### `scripts/fetch-gnews.ps1`

负责：

- 拉取 GNews
- 时间窗口控制
- 去重
- 黑名单过滤
- 分类聚合

### `scripts/score-and-select.ps1`

负责：

- 评分
- 选出可供模型改写的文章

### `scripts/generate_image_urls.ps1`

负责：

- 调图片 API
- 读取 `url` 或 `b64_json`
- 保存本地图片
- 将 PNG 转成 WebP
- 输出 `generatedImagePath`

### `scripts/write_lark_records.ps1`

负责：

- 校验记录格式
- 创建飞书记录
- 上传图片附件到 `图片` 字段

### `scripts/setup.ps1`

负责：

- 首次配置环境变量
- 帮你保存本机运行配置

## 当前真实验证结论

我们已经做过真实验证，不是理论设计：

- 单条端到端验证通过
- 5 条批量端到端验证通过
- 图片生成 -> 转 WebP -> 飞书记录创建 -> 飞书附件上传 全部成功

这意味着现在这套仓库已经不只是“脚本能跑”，而是整条业务链路已经验证过可行。

## 上传 GitHub 前的注意事项

### 绝对不要提交这些内容

- `GNEWS_API_KEY`
- `IMAGE_API_KEY`
- 任何公司内网地址中带凭证的信息
- 任何本机专有路径
- 本地测试生成图片
- 本地运行产物

### 当前已经被忽略的内容

`.gitignore` 已忽略：

- `processed/`
- `data/`
- `records.normalized.json`
- `lark-batch-create.json`

### 推荐上传的内容

应该上传：

- `scripts/`
- `references/`
- `README.md`
- `SKILL.md`
- `agents/`
- `LICENSE`

不应该上传：

- 本地测试图片
- 本地批量测试 JSON
- 任何临时输出文件

## 常见问题

### 1. 为什么图片生成成功了，但 `生成图片` 字段可能还是空？

因为图片接口可能返回的是 `b64_json`，不是远程 URL。

这时图片已经生成成功，只是通过本地文件再上传飞书附件字段 `图片`。

### 2. 为什么以前状态会写成失败？

旧逻辑只认 `generatedImageUrl`。

现在已经修正：

- 只要本地文件成功生成，状态也会记成 `已生成`

### 3. 为什么 WebP 比 PNG 小很多？

因为 WebP 压缩效率更高，适合飞书附件上传和后续存储。

### 4. 为什么别人拿到仓库后不能直接跑？

因为这个仓库依赖你自己的：

- GNews Key
- 飞书权限
- 图片 API
- Python 环境

这些必须自己配置，不能从仓库里继承。
