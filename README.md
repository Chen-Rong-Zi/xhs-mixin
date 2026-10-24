# xhs-query — Xiaohongshu Query mixin kit (sbx v2)

一个 Docker Sandboxes (sbx) `schemaVersion: "2"` 的 **mixin kit**，让沙箱里的 agent 通过
`xhs-mcp` MCP server 查询小红书（Xiaohongshu）帖子与信息流。

- 网络白名单覆盖 xiaohongshu 主机族 + 图片 CDN：`xiaohongshu.com` / `*.xiaohongshu.com` /
  `xhscdn.com` / `*.xhscdn.com`（运行时搜索 API `edith.xiaohongshu.com`、站点
  `www.xiaohongshu.com`、图片 CDN `sns-webpic-qc.xhscdn.com` 等子域都在内）。
- MCP server 是 **jobsonlook/xhs-mcp** —— 基于「JS 逆向 x-s/x-t 签名 + 直连 HTTP API」的
  Python 服务（不是旧版的 npm/Puppeteer 页面自动化）。代码在 kit 内**内置补丁版**
  `files/workspace/xhs-mcp-src/`，用 `uv run --project ./xhs-mcp-src python -m xhs_mcp`
  启动。相对上游的补丁：
  1. `search_notes` 工具新增 **`count` 参数**，按页翻页凑齐指定条数（这是租房爬虫要的
     「抓取指定数量帖子」能力，上游只返回固定一页 20 条）；
  2. cookie 解析在 `XHS_COOKIE` 未设置/为 sbx 哨兵 `proxy-managed` 时**回退读
     `~/.xhs-mcp/cookies.json`**，让 kit 现有的 cookie 自动安装流程原样可用；
  3. `mcp` 依赖锁定 `<2`（上游在 mcp 2.x 下 FastMCP 改名直接崩）。
- Cookie bundle 由宿主机托管（`sbx secret set xhs`），创建沙箱时 `--env XHS_COOKIE` 注入，
  再在沙箱内跑 `xhs-install-cookie.sh` 清洗成 `~/.xhs-mcp/cookies.json`；新 server 的
  `resolve_cookie()` 会回退读它（详见「凭证提供方式」）。
- 提供 MCP 配置与使用指南，agent 在沙箱内即可调用 `search_notes`（可指定条数）/
  `get_note_content` / `get_note_comments` / `home_feed` / `check_cookie` /
  `post_comment`。**没有** `xhs_auth_*` 登录工具（本 server 纯 cookie 认证）。

## 文件结构

```
xhs-mixin/
├── spec.yaml                 # v2 mixin 规格：网络白名单、凭证、agent instructions
├── Dockerfile                # 配套件：预烘焙 jobsonlook MCP 运行时（uv + Python + Chromium）
├── context.md                # 规范源副本（与 files/workspace/context.md 一致）
├── README.md                 # 本文件
├── files/
│   └── workspace/
│       ├── .mcp.json              # 工作区根的 MCP 配置（claude 只自动发现工作区根的 .mcp.json）
│       ├── xhs-install-cookie.sh  # cookie 清洗安装脚本：→ ~/.xhs-mcp/cookies.json
│       ├── xhs-mcp-src/           # 内置补丁版 jobsonlook/xhs-mcp（Python 包，uv run 启动）
│       └── context.md             # 注入到 /workspace/context.md 的使用指南
└── scripts/
    ├── validate.sh           # sbx kit validate --offline
    └── build.sh              # sbx kit pack + 显示包内容
```

## 使用步骤（宿主机执行）

mixin 只是 kit 源码，沙箱内部不能自己加载，必须在宿主机上操作：

```bash
# 1) 校验 kit 合法性
sbx kit validate ./xhs-mixin --offline

# 2) 打包成 zip（可选，发布用）
sbx kit pack ./xhs-mixin --output dist/xhs-query.kit.zip

# 3) 加载 mixin 运行（宿主机，必须用 --kit；工作区 . 会挂载）。
#    若要让沙箱内 XHS_COOKIE 拿到真实 cookie bundle（xhs-install-cookie.sh 需要），
#    创建时用 --env XHS_COOKIE 注入（裸 KEY 从当前宿主机环境读取，值来自 sbx secret 托管的那份 bundle）：
#    XHS_COOKIE="$(cat ~/Downloads/www.xiaohongshu.com_json_*.json)" sbx run claude --kit ./xhs-mixin/ .
sbx run claude --kit ./xhs-mixin/ .

# 4) 若已有沙箱，也可用 sbx kit add 添加
sbx kit add <sandbox> ./xhs-mixin
```

> **镜像前置**：jobsonlook MCP 需要 Python 3.12+、`uv` 和 Playwright Chromium。`claude:full`
> 镜像自带 Python 3.14 + `uv`，但**没有浏览器**。首次使用需
> `python -m playwright install --with-deps chromium`（或把 Chromium 烘焙进镜像，见
> 「预烘焙镜像」）。这是镜像前置，kit 配置本身不依赖它。

## 获取 Cookie（secret）

secret = 小红书**网页登录 Cookie**：由 `a1` / `webId` / `web_session` 等字段组成的 **Cookie
header 串**（形如 `a1=xxx; webId=yyy; web_session=zzz`），或 Chrome 导出的 cookie JSON 数组
（15 条）。两种获取方式：

1. **方法①（推荐，宿主机浏览器手动导出）**：浏览器无痕访问 www.xiaohongshu.com → 登录 →
   F12 开发者工具 → Network 面板 → 复制任意请求的 Cookie 头整段；或直接用 Chrome 插件
   「Export Cookies」导出 JSON 数组文件（落到 `~/Downloads/www.xiaohongshu.com_json_*.json`）。
2. **方法②（拼装）**：若已有 `~/.xhs-mcp/cookies.json`，把其中各字段拼成 `name=value;
   name2=value2` 的 Cookie 串。

拿到 Cookie 后按「凭证提供方式」把它作为 service secret 登记（`sbx secret set xhs`），并在
创建沙箱时注入 `XHS_COOKIE`；然后跑 `xhs-install-cookie.sh` 即可让 server 用上（无需扫码）。

## 凭证提供方式

server 的登录态来源：`XHS_COOKIE` 环境变量（Cookie 串）优先，未设置/为哨兵时回退
`~/.xhs-mcp/cookies.json`。两条主路径：

- **路径 A（推荐）：secret → env → 清洗安装**。Cookie bundle（Chrome「导出 cookies」JSON
  数组，15 条）由宿主机 sbx secret 托管，创建沙箱时用 `--env XHS_COOKIE` 注入沙箱环境，
  沙箱内跑 `xhs-install-cookie.sh` 清洗（去掉 session cookie 的 `expires`、把 float
  `expirationDate` 截成 int `expires`）写入 `~/.xhs-mcp/cookies.json`；server 的
  `resolve_cookie()` 回退读取它。这是**幂等、可脚本化**的路径，登录态与宿主机保持同步，
  cookie 过期时重登后重跑一次即可。
- **路径 B（可选）：宿主机 binding + 代理注入**。`~/.config/sbx/credentials.yaml` 有
  service `xhs` 的 binding 时，沙箱出口代理向白名单域（`edith.xiaohongshu.com` /
  `xiaohongshu.com` 等）的请求注入 Cookie 头。**注意**：本 server 的签名请求由浏览器子进程
  发起，该注入路径对浏览器流量**未经实测**——不要依赖它，用路径 A。

### 宿主机登记命令（路径 A）

```bash
# 1) cookie bundle（Chrome 导出的 JSON 数组文件）存为 service secret "xhs"
printf '%s' "$(cat ~/Downloads/www.xiaohongshu.com_json_*.json)" | sbx secret set xhs
sbx secret ls                       # 应看到 service 类型 xhs (stored)

# 2) 创建沙箱时把同一份 bundle 注入 XHS_COOKIE（裸 KEY 从当前宿主机环境读取）
XHS_COOKIE="$(cat ~/Downloads/www.xiaohongshu.com_json_*.json)" \
  sbx run claude --kit ./xhs-mixin/ .

# 3) 沙箱内（工作区根目录）清洗安装：
#    sh xhs-install-cookie.sh
#    预期输出 "Installed 15 cookies"，其中 2 个 session（无 expires）。
```

> **警告**：`XHS_COOKIE=$(cat …)` 的值只在创建瞬间进进程环境，不写入任何 kit 文件。切勿把
> cookie 直接粘贴进 `--env XHS_COOKIE='…'` 的字面量（会落 shell 历史/进程列表）。

### binding 与 proxyManaged 的作用

- kit 的 `credentials[].apiKey.name: XHS_COOKIE` + `proxyManaged: true` 声明了 service `xhs`
  的 gated credential：**没有 binding 时创建沙箱会打印**
  `Note: no binding authorizes xhs — the credential was not injected. …`（第三方 kit 凭证的
  默认行为，非 bug）。本仓库已在 `~/.config/sbx/credentials.yaml` 为 `xhs` 添加 binding
  （domains 覆盖 `*.xiaohongshu.com` / `*.xhscdn.com` 族），创建时不再告警。
- `proxyManaged: true` 时引擎默认把容器内 `XHS_COOKIE` 设为哨兵 `proxy-managed`；**显式传入
  的 `--env XHS_COOKIE` 会覆盖哨兵**（实测生效），两者可共存：路径 A 读 `--env` 的真实值，
  路径 B 的代理注入照常工作。没有 binding 也不影响路径 A（`--env` 独立于 binding）。
- server 的 `resolve_cookie()` 会把哨兵 `proxy-managed` 视为「未设置」，回退读
  `~/.xhs-mcp/cookies.json`，所以即使忘记 `--env`，baked cookie 也能兜底。

## 泄密面（XHS_COOKIE 与 .mcp.json）

工作区根的 `.mcp.json` 里没有 cookie 字面量；server 命令是
`sh xhs-install-cookie.sh ...; exec uv run --project ./xhs-mcp-src python -m xhs_mcp`，
cookie 经 `xhs-install-cookie.sh` 清洗进 `~/.xhs-mcp/cookies.json`，server 回退读取。
真实值只存在于：宿主机 secret 存储、创建瞬间的宿主进程环境、以及沙箱 env / 清洗后的
`~/.xhs-mcp/cookies.json`；kit 文件里没有任何 cookie 字面量（`xhs-cookies.json` 已
gitignore，绝不入库）。

## 抓取指定数量的帖子

`search_notes(keywords="上海 租房", count=50)` 会**翻页凑齐最多 50 条**：工具内部按
page_size=20 循环调用搜索 API，直到收满 `count` 条或 API 无更多结果。上游工具只有固定一页
20 条且无 count 参数，这是 kit 内置补丁的核心动机（租房爬虫批量取数）。注意 XHS 反爬：连续
大批量请求会触发 461/风控，请控制频率（见「风险提醒」）。

## 直连出口要求（签名 API + 浏览器）

jobsonlook/xhs-mcp 用真实浏览器加载 `www.xiaohongshu.com/explore` 复用其签名运行时
（`_webmsxyw`）计算 `X-S`/`X-T`/`X-S-Common`。sbx 出口代理（`gateway.docker.internal:3128`）
会对 TLS 重新 originate，小红书看到非 Chrome 指纹会标记会话（`user/me` → `code=-100/-101`，
搜索 → `461`，页面 → 跳 `website-login/error?error_code=300012 IP存在风险`）。本 kit 已在
工作区根 `.mcp.json` 给 xhs-mcp server 设了 `env.NO_PROXY=*`（含小写 `no_proxy`）——server
起浏览器是它的子进程、继承该 env，于是**直连** `*.xiaohongshu.com` / `*.xhscdn.com`（两者都
在网络白名单，直连放行）。**这个 env 必须保留**，是签名 API + 浏览器能工作的前提。

## 预烘焙镜像（可选）

网络白名单里**不含 pypi.org / npmjs.org**，沙箱运行时 `uv run` 首次会去下载依赖，可能被网络
策略拦截。因此提供配套 `Dockerfile` 预装运行时（uv + 项目依赖 + Playwright Chromium）：

```bash
docker build -t xhs-mcp-runtime:1 .
```

然后用 `sbx template` / `sbx run` 指定该镜像。

## 风险提醒（重要）

- **小红书反爬**：Cookie 与设备指纹绑定，API 有 461/460 反爬错误码、频率限制，风控严重时有
  封号风险；仅用于低频只读查询，避免批量抓取。连续请求被 461 后会话会被标记
  （`-100 登录已过期`）或 egress IP 被标记（`300012 IP存在风险`），需等待数分钟再试。
- **Cookie 有效期**：登录 Cookie 会过期（几小时~几天），过期会导致搜索/详情接口返回
  -100/-101。cookie 过期后重新导出 bundle → 宿主机 `sbx secret set xhs` 重存 → 重建沙箱并
  `--env XHS_COOKIE` → 沙箱内重跑 `xhs-install-cookie.sh`。
- **合规**：仅供学习/个人低频查询，勿用于商业批量采集；数据版权归小红书。

## 验证命令（scripts/ 里也有）

```bash
bash scripts/validate.sh    # sbx kit validate --offline
bash scripts/build.sh       # sbx kit pack + 显示 inspect
```

## MCP 工具表

| 工具 | 用途 | 参数 |
|------|------|------|
| `search_notes` | 按关键词搜索笔记，**可指定条数（翻页凑齐）** | `keywords`（必填）, `count`（可选，默认 20） |
| `get_note_content` | 获取笔记完整详情（标题/作者/时间/点赞/评论/收藏/正文/封面） | `url`（必填，需含 `xsec_token`） |
| `get_note_comments` | 获取笔记评论 | `url`（必填，需含 `xsec_token`） |
| `home_feed` | 获取首页推荐信息流 | — |
| `check_cookie` | 检测 cookie 是否有效 | — |
| `post_comment` | 发布评论到指定笔记（慎用） | `note_id`, `comment` |

所有工具都挂在 `xhs-mcp` MCP server 下；**没有任何工具带 cookie 参数**，登录态由
`XHS_COOKIE` env 或 `~/.xhs-mcp/cookies.json` 提供（路径 A 的 `xhs-install-cookie.sh` 生成）。
工具名与旧 server 不同：搜索 `search_notes`（旧 `xhs_search_note`）、详情
`get_note_content`（旧 `xhs_get_note_detail`）、信息流 `home_feed`（旧
`xhs_discover_feeds`），且**没有** `xhs_auth_*` 登录工具。
