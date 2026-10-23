# xhs-query — Xiaohongshu Query mixin kit (sbx v2)

一个 Docker Sandboxes (sbx) `schemaVersion: "2"` 的 **mixin kit**，让沙箱里的 agent 通过
`xhs-mcp` MCP server 查询小红书（Xiaohongshu）帖子与信息流。

- 网络白名单严格最小化：只允许 `xiaohongshu.com` / `edith.xiaohongshu.com`。
- 凭证由宿主机托管（本地 custom secret）：容器内 `XHS_COOKIE` 是占位符值，真实 cookie 只在宿主机 secret 存储，proxy 在发往白名单域的请求头里做占位符→真实替换。
- 提供 MCP 配置与使用指南，agent 在沙箱内即可调用 `xhs_search_note` /
  `xhs_get_note_detail` / `xhs_discover_feeds` 三个工具。

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

## 凭证提供方式

XHS cookie 不是 kit 里的文件，而是你在宿主机上提供的本地 **custom secret**。本地模式使用
**占位符替换机制**：`sbx secret set-custom` 把真实值登记在宿主机的 secret 存储中，把占位符值
设为 `--env` 指定的环境变量，proxy 在发往白名单内域的请求上把占位符替换成真实 cookie——
cookie 值不会进入沙箱文件系统。

```bash
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

含义：custom secret 的 env 占位符替换**已生效**（沙箱内 `XHS_COOKIE` = 占位符值，proxy 在发往
白名单域的请求上替换为真实 cookie）；但 kit 的 `credentials[].service: xhs` 声明把 xhs 标记为
**gated credential service**，其「Cookie 头注入」路径需要宿主机有对应 **binding** 才激活，
否则就打印上面的提示。这是 sbx 的正常行为（所有 kit 声明的凭证都要求宿主绑定，如
`ANTHROPIC_API_KEY` 同理），不是 bug。

解决办法（任选其一）：

1. 交互式：不带 `--detach` 运行 `sbx run claude --kit ./xhs-mixin/ .`，按提示绑定 xhs 凭证；
2. 手动：编辑 `~/.config/sbx/credentials.yaml` 添加 service `xhs` 的 binding（sbx 官方提示
   也是这么建议的；该文件的字段格式请参考 sbx 文档，勿凭猜测填写）。

不建 binding 也**不影响使用**：只要 MCP server 把 `XHS_COOKIE`（占位符）当作 cookie 值发出去，
proxy 的 custom-secret 替换仍能让真实 cookie 生效；建了 binding 后，kit 声明的注入路径也一并
激活，两种方式可以并存。

注入效果：

- 容器环境变量 `XHS_COOKIE` 是**占位符值**（不是真实 cookie）。
- 真实 cookie 只存在于宿主机 secret 存储；proxy 在发往
  `edith.xiaohongshu.com` / `xiaohongshu.com` 的请求头上做占位符→真实替换。

spec.yaml 里的 `credentials[].apiKey.name: XHS_COOKIE`、`proxyManaged: true` 即对应这套托管逻辑。

## 占位符与泄密面

`.mcp/xhs-mcp.json` 里 `env.XHS_COOKIE: "${XHS_COOKIE}"` 由 claude 插值成容器里的
**占位符值**（不是真实 cookie）；真实 cookie 只在宿主机 proxy 层，永不进入沙箱文件系统或
容器 env。维护者不要误以为容器 env 里就是真实 cookie 值。

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
  cookie 的权威来源是宿主机 `sbx secret set-custom`（更新同一 secret）；`npx xhs-mcp login`
  只在宿主机有该 CLI 时用来获取新的 web 登录 cookie，然后把新 cookie 重新 set-custom。
- **合规**：仅供学习/个人低频查询，勿用于商业批量采集；数据版权归小红书。

## 验证命令（scripts/ 里也有）

```bash
bash scripts/validate.sh    # sbx kit validate --offline
bash scripts/build.sh       # sbx kit pack + 显示 inspect
```

## MCP 工具表

| 工具 | 用途 | 参数 |
|------|------|------|
| `xhs_search_note` | 按关键词搜索笔记 | keyword, page, page_size, sort, note_type, cookie |
| `xhs_get_note_detail` | 按 id 获取笔记完整详情（标题/正文/图片/点赞/评论…） | note_id, cookie, is_xsec_req |
| `xhs_discover_feeds` | 获取推荐信息流 | page, page_size, cookie |

所有工具都挂在 `xhs-mcp` MCP server 下；`cookie` 参数一般无需手动传，proxy 已在请求头里注入
真实 `Cookie`（`.mcp/xhs-mcp.json` 的 `env.XHS_COOKIE: "${XHS_COOKIE}"` 是容器内的占位符值，
见「占位符与泄密面」）。
