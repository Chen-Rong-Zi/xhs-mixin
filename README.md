# xhs-query — Xiaohongshu Query mixin kit (sbx v2)

一个 Docker Sandboxes (sbx) `schemaVersion: "2"` 的 **mixin kit**，让沙箱里的 agent 通过
`xhs-mcp` MCP server 查询小红书（Xiaohongshu）帖子与信息流。

- 网络白名单覆盖 xiaohongshu 主机族 + 图片 CDN：`xiaohongshu.com` / `*.xiaohongshu.com` /
  `xhscdn.com` / `*.xhscdn.com`（运行时搜索 API `so.xiaohongshu.com`、`as.xiaohongshu.com`、
  图片 CDN `sns-webpic-qc.xhscdn.com` 等子域都在内）。
- xhs-mcp 是 **Puppeteer 浏览器自动化** MCP server，驱动 `www.xiaohongshu.com` 页面并读取页面
  `__INITIAL_STATE__` 数据；登录态只从 `~/.xhs-mcp/cookies.json` 读取（appDataDir = `~/.xhs-mcp`），
  **不直接读 `XHS_COOKIE` 环境变量，工具也无 cookie 参数**。
- Cookie bundle 由宿主机 sbx secret 托管（`sbx secret set xhs`），创建沙箱时用 `--env XHS_COOKIE`
  注入沙箱环境，再在沙箱内跑 `xhs-install-cookie.sh` 清洗成 `~/.xhs-mcp/cookies.json`（详见
  「凭证提供方式」）；备选：沙箱内 `xhs_auth_login` 扫码登录。
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
│       ├── .mcp.json              # 工作区根的 MCP 配置（claude 只自动发现工作区根的 .mcp.json）
│       ├── xhs-install-cookie.sh  # cookie 清洗安装脚本：$XHS_COOKIE → ~/.xhs-mcp/cookies.json
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

拿到 Cookie 后按「凭证提供方式」把它作为 service secret 登记（`sbx secret set xhs`），并在创建
沙箱时注入 `XHS_COOKIE`；然后跑 `xhs-install-cookie.sh` 即可让 xhs-mcp 用上（无需扫码）。

## 凭证提供方式

xhs-mcp 的登录态默认在 `~/.xhs-mcp/cookies.json`。让 xhs-mcp 用上真实 cookie 的三条路径：

- **路径 A（推荐）：secret → env → 清洗安装**。Cookie bundle（Chrome「导出 cookies」JSON 数组，
  15 条）由宿主机 sbx secret 托管，创建沙箱时用 `--env XHS_COOKIE` 注入沙箱环境，沙箱内跑
  `xhs-install-cookie.sh` 清洗（去掉 session cookie 的 `expires`、把 float `expirationDate` 截成
  int `expires`）写入 `~/.xhs-mcp/cookies.json`。这是**幂等、可脚本化**的路径，登录态与宿主机
  保持同步，cookie 过期时重登后重跑一次即可。
- **路径 B：沙箱内扫码登录**。在沙箱里调用 `xhs_auth_login`（或 `npx xhs-mcp login`），弹出浏览器
  后手机 App 扫码，登录态写入沙箱内 `~/.xhs-mcp/cookies.json`。`*.xiaohongshu.com` 在网络白名单
  内，沙箱可直接访问。此路径不依赖宿主机托管 secret，但登录态只活在沙箱里。
- **路径 C（可选）：宿主机 binding + 代理注入**。`~/.config/sbx/credentials.yaml` 有 service `xhs`
  的 binding 时，沙箱出口代理向白名单域（`edith.xiaohongshu.com` / `xiaohongshu.com` 等）的请求
  注入 Cookie 头。**注意**：xhs-mcp 本身不读 `XHS_COOKIE` 环境变量（它是浏览器自动化，不是 HTTP
  请求客户端），该注入路径对浏览器流量**未经实测**——不要依赖它，用路径 A。

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

> **警告**：`XHS_COOKIE=$(cat …)` 的值只在创建瞬间进进程环境，不写入任何 kit 文件。切勿把 cookie
> 直接粘贴进 `--env XHS_COOKIE='…'` 的字面量（会落 shell 历史/进程列表）。

### binding 与 proxyManaged 的作用

- kit 的 `credentials[].apiKey.name: XHS_COOKIE` + `proxyManaged: true` 声明了 service `xhs` 的
  gated credential：**没有 binding 时创建沙箱会打印**
  `Note: no binding authorizes xhs — the credential was not injected. …`（第三方 kit 凭证的默认
  行为，非 bug）。本仓库已在 `~/.config/sbx/credentials.yaml` 为 `xhs` 添加 binding（domains 覆盖
  `*.xiaohongshu.com` / `*.xhscdn.com` 族），创建时不再告警。
- `proxyManaged: true` 时引擎默认把容器内 `XHS_COOKIE` 设为哨兵 `proxy-managed`；**显式传入的
  `--env XHS_COOKIE` 会覆盖哨兵**（实测生效），两者可共存：路径 A 读 `--env` 的真实值，路径 C 的
  代理注入照常工作。没有 binding 也不影响路径 A（`--env` 独立于 binding）。

## 泄密面（XHS_COOKIE 与 .mcp.json）

工作区根的 `.mcp.json` 里 `env.XHS_COOKIE: "${XHS_COOKIE}"` 由 claude 从沙箱环境插值。创建沙箱时
用了 `--env XHS_COOKIE` 的话，容器 env 就是**真实 cookie bundle**（不是哨兵），`.mcp.json` 插值也
拿到真实值。注意 **xhs-mcp 本身不读 `XHS_COOKIE` 环境变量，工具也没有 cookie 参数**——让 xhs-mcp
用上登录态的是路径 A 生成的 `~/.xhs-mcp/cookies.json`。真实值只存在于：宿主机 secret 存储、
创建瞬间的宿主进程环境、以及沙箱 env / 清洗后的 `~/.xhs-mcp/cookies.json`；kit 文件里没有任何
cookie 字面量。

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
  cookie 过期后重新导出 bundle → 宿主机 `sbx secret set xhs` 重存 → 重建沙箱并 `--env XHS_COOKIE`
  → 沙箱内重跑 `xhs-install-cookie.sh`；或直接在**沙箱内重新调用 `xhs_auth_login`** 刷新登录态。
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
`~/.xhs-mcp/cookies.json` 提供（路径 A 的 `xhs-install-cookie.sh` 或路径 B 的 `xhs_auth_login`
生成）。`browser_path` 可选，指向自定义 Chromium 可执行文件路径，默认使用 xhs-mcp 自动安装的
浏览器。工作区根 `.mcp.json` 的 `env.XHS_COOKIE: "${XHS_COOKIE}"` 由 claude 从沙箱环境插值；
创建时用 `--env XHS_COOKIE` 注入后它就是真实 bundle（见「泄密面」），但 xhs-mcp 的登录态不靠它。
