# xhs-query — Xiaohongshu Query mixin kit (sbx v2)

一个 Docker Sandboxes (sbx) `schemaVersion: "2"` 的 **mixin kit**，让沙箱里的 agent 通过
`xhs-mcp` MCP server 查询小红书（Xiaohongshu）帖子与信息流。

- 网络白名单严格最小化：只允许 `xiaohongshu.com` / `edith.xiaohongshu.com`。
- xhs-mcp 是 **Puppeteer 浏览器自动化** MCP server，驱动 `www.xiaohongshu.com` 页面并读取页面
  `__INITIAL_STATE__` 数据；登录态只从 `~/.xhs-mcp/cookies.json` 读取（appDataDir = `~/.xhs-mcp`），
  **不读 `XHS_COOKIE` 环境变量，工具也无 cookie 参数**。
- 容器内 `XHS_COOKIE` 只是宿主机 secret 的**占位符**（信息性）。真实让 xhs-mcp 用上的登录态走
  **沙箱内 `xhs_auth_login`**（推荐）或 **宿主机 binding + 代理注入**（可选、对浏览器流量未实测）
  两条路径，详见下文。
- 提供 MCP 配置与使用指南，agent 在沙箱内即可调用 `xhs_search_note` / `xhs_get_note_detail` /
  `xhs_discover_feeds` 三个查询工具，以及 `xhs_auth_login` / `xhs_auth_logout` / `xhs_auth_status`
  三个登录工具。

## 文件结构

```
xhs-mixin/
├── spec.yaml                 # v2 mixin 规格：网络白名单、凭证、agent instructions
├── Dockerfile                # 配套件：预烘焙 xhs-mcp + Chromium 运行时镜像
├── context.md                # 规范源副本（与 files/workspace/context.md 一致）
├── README.md                 # 本文件
├── files/
│   └── workspace/
│       ├── .mcp/xhs-mcp.json # 注入到工作区的 MCP 配置（claude 读取）
│       └── context.md        # 注入到 /workspace/context.md 的使用指南
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

# 3) 加载 mixin 运行（宿主机，必须用 --kit；工作区 . 会挂载）
sbx run claude --kit ./xhs-mixin/ .

# 4) 若已有沙箱，也可用 sbx kit add 添加
sbx kit add <sandbox> ./xhs-mixin
```

## 获取 Cookie（secret）

secret = 小红书**网页登录 Cookie**：由 `a1` / `webId` / `web_session` 等字段组成的 **Cookie header
串**（形如 `a1=xxx; webId=yyy; web_session=zzz`）。三种获取方式：

1. **方法①（推荐，宿主机 CLI）**：用 xhs-mcp 自带 CLI 弹出浏览器扫码登录并保存登录态：

   ```bash
   npm i -g xhs-mcp@0.8.13
   xhs-mcp browser                  # 安装/校验 xhs-mcp 自带的 Chromium
   xhs-mcp login --timeout 120      # 弹出浏览器 → 手机小红书 App 扫码 → 登录态存 ~/.xhs-mcp/cookies.json
   ```

   得到的 `~/.xhs-mcp/cookies.json` 就是权威登录态（xhs-mcp 只认它）。

2. **方法②（浏览器手动）**：浏览器无痕访问 www.xiaohongshu.com → 登录 → F12 开发者工具 →
   Network 面板 → 复制任意请求的 Cookie 头整段。

3. **方法③（拼装）**：若已有 `~/.xhs-mcp/cookies.json`，把其中各字段拼成 `name=value; name2=value2`
   的 Cookie 串。

拿到 Cookie 串后可 `sbx secret set-custom` 登记为宿主机 custom secret（见下节），但 xhs-mcp 的
**推荐**做法是在沙箱内 `xhs_auth_login` 直接扫码（见「凭证提供方式」）。

## 凭证提供方式

xhs-mcp 的登录态默认在 `~/.xhs-mcp/cookies.json`。让 xhs-mcp 用上真实 cookie 有两条路径：

- **路径 A：沙箱内登录（推荐）**。在沙箱里调用 `xhs_auth_login`（或 `npx xhs-mcp login`），弹出
  浏览器后手机 App 扫码，登录态写入沙箱内 `~/.xhs-mcp/cookies.json`。`www.xiaohongshu.com` 已在
  网络白名单内，沙箱可直接访问。此路径不依赖宿主机托管任何 secret。
- **路径 B：宿主机 custom secret + 代理注入（可选）**。`sbx secret set-custom` 把 Cookie 登记在
  宿主机 secret 存储，把占位符值设进容器 `XHS_COOKIE` 环境变量；若 `~/.config/sbx/credentials.yaml`
  有 service `xhs` 的 binding，沙箱出口代理会向白名单域请求注入 Cookie 头。
  **注意**：xhs-mcp 本身不读 `XHS_COOKIE` 环境变量（它是浏览器自动化，不是 HTTP 请求客户端），
  且该注入路径对浏览器流量**未经实测**——因此优先用路径 A。

```bash
# 路径 B 的登记命令（宿主机）：
# 推荐：cookie 存到 0600 文件，用 --command 读取，避免明文进 shell 历史/进程列表
read -rs -p 'XHS cookie: ' c && umask 077 && printf '%s' "$c" > ~/.xhs_cookie
sbx secret set-custom \
  --host xiaohongshu.com --host edith.xiaohongshu.com \
  --env XHS_COOKIE \
  --command "cat $HOME/.xhs_cookie"

# 或从环境变量传入（值不进 shell 历史，但运行瞬间对 ps 可见）：
# sbx secret set-custom --host xiaohongshu.com --host edith.xiaohongshu.com \
#   --env XHS_COOKIE --value "$XHS_COOKIE"

sbx secret ls   # 查看占位符
sbx secret rm --placeholder <PLACEHOLDER> -f   # 移除/更新
```

> **警告**：切勿把真实 cookie 直接粘贴进 `--value` 命令行参数——会落入 shell 历史与进程列表。
> `--command` 的 helper 路径必须是**绝对路径**，且位于共享挂载之外。

注意：本地模式的 `sbx secret set-custom` 不支持 `--name`/`--header`/`--format`（这些是
`--cloud` 专属）；`xhs` 也非内置服务，不要用 `sbx secret set xhs`。

### 首次运行可能看到 `no binding authorizes xhs`

用 `sbx run claude --kit ./xhs-mixin/ .` 创建沙箱时，即使已用上面的命令设好 custom secret，
输出里仍可能出现：

```
Note: no binding authorizes xhs — the credential was not injected. Create a binding
(re-run interactively, or edit ~/.config/sbx/credentials.yaml) to use it.
```

含义：custom secret 的 env 占位符替换**已生效**（沙箱内 `XHS_COOKIE` = 占位符值）；但 kit 的
`credentials[].service: xhs` 声明把 xhs 标记为 **gated credential service**，其「代理注入 Cookie
头」路径需要宿主机有对应 **binding** 才激活，否则就打印上面的提示。这是 sbx 的正常行为（所有 kit
声明的凭证都要求宿主绑定，如 `ANTHROPIC_API_KEY` 同理），不是 bug。

**即使不建 binding，沙箱内 `xhs_auth_login` 也能正常使用**——xhs-mcp 不依赖 `XHS_COOKIE`，它
自己在沙箱内扫码登录写 `~/.xhs-mcp/cookies.json`，可以完全绕过 binding 直接可用。

解决办法（任选其一）：

1. 交互式：不带 `--detach` 运行 `sbx run claude --kit ./xhs-mixin/ .`，按提示绑定 xhs 凭证；
2. 手动：编辑 `~/.config/sbx/credentials.yaml` 添加 service `xhs` 的 binding（sbx 官方提示
   也是这么建议的；该文件的字段格式请参考 sbx 文档，勿凭猜测填写）。

注入效果：

- 容器环境变量 `XHS_COOKIE` 是**占位符值**（不是真实 cookie）。
- 真实 cookie 只存在于宿主机 secret 存储；proxy 在发往 `edith.xiaohongshu.com` /
  `xiaohongshu.com` 的请求头上做占位符→真实替换（仅对非浏览器 HTTP 流量有效；xhs-mcp 的浏览器
  流量不走这条路径，其登录态来自沙箱内 `~/.xhs-mcp/cookies.json`）。

spec.yaml 里的 `credentials[].apiKey.name: XHS_COOKIE`、`proxyManaged: true` 即对应这套托管逻辑。

## 占位符与泄密面

`.mcp/xhs-mcp.json` 里 `env.XHS_COOKIE: "${XHS_COOKIE}"` 由 claude 插值成容器里的**占位符值**
（不是真实 cookie）。要强调：**xhs-mcp 不读 `XHS_COOKIE` 环境变量，工具也没有 cookie 参数**，所以
`--env XHS_COOKIE` 的 custom secret 只是把占位符放进环境变量，服务于「宿主机 binding + 代理注入」
路径（对浏览器流量未实测）；真正让 xhs-mcp 用上登录态、可靠的方式是**沙箱内 `xhs_auth_login`**
扫码登录，登录态写入沙箱内 `~/.xhs-mcp/cookies.json`，之后所有工具自动带上该登录态。维护者不要
误以为容器 env 里就是真实 cookie 值，也不要指望改 env 就能给 xhs-mcp 注入 cookie。

## 预烘焙镜像（可选）

网络白名单里**不含 npmjs.org**，沙箱运行时 `npx` 首次运行会去下载 `xhs-mcp`，可能被网络策略拦截。
因此提供配套 `Dockerfile` 预装运行时：

```bash
docker build -t xhs-mcp-runtime:1 .
```

然后用 `sbx template` / `sbx run` 指定该镜像。镜像内已全局安装 `xhs-mcp@0.8.13` 并装好
puppeteer 需要的 Chromium（`xhs-mcp` 通过无头 Chromium 抓取小红书，必须装浏览器）。

## 风险提醒（重要）

- **小红书反爬**：Cookie 与设备指纹绑定，API 有 461/460 反爬错误码、频率限制，风控严重时有封号风险；
  仅用于低频只读查询，避免批量抓取。
- **Cookie 有效期**：登录 Cookie 会过期（几小时~几天），过期会导致搜索/详情接口返回 401/461。
  cookie 过期后，在**沙箱内重新调用 `xhs_auth_login`**（或宿主机重新 `set-custom` 刷新）即可更新
  登录态。
- **合规**：仅供学习/个人低频查询，勿用于商业批量采集；数据版权归小红书。

## 验证命令（scripts/ 里也有）

```bash
bash scripts/validate.sh    # sbx kit validate --offline
bash scripts/build.sh       # sbx kit pack + 显示 inspect
```

## MCP 工具表

| 工具 | 用途 | 参数 |
|------|------|------|
| `xhs_search_note` | 按关键词搜索笔记 | `keyword`（必填）, `browser_path`（可选） |
| `xhs_get_note_detail` | 按 id 获取笔记完整详情（标题/正文/图片/点赞/评论…） | `feed_id`（必填）, `xsec_token`（必填）, `browser_path`（可选） |
| `xhs_discover_feeds` | 获取推荐信息流 | `browser_path`（可选） |
| `xhs_auth_login` | 登录小红书（弹出浏览器，手机 App 扫码） | `browser_path`（可选） |
| `xhs_auth_logout` | 退出登录 / 清除已保存 cookies | — |
| `xhs_auth_status` | 查看当前登录状态 | — |

所有工具都挂在 `xhs-mcp` MCP server 下；**没有任何工具带 cookie 参数**，xhs-mcp 的登录态由
`~/.xhs-mcp/cookies.json` 提供（沙箱内 `xhs_auth_login` 生成）。`browser_path` 可选，指向自定义
Chromium 可执行文件路径，默认使用 xhs-mcp 自动安装的浏览器。`.mcp/xhs-mcp.json` 的
`env.XHS_COOKIE: "${XHS_COOKIE}"` 只是容器内的占位符值（见「占位符与泄密面」），不参与登录态。
