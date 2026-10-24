# v2 kit（schemaVersion "2"）secret/凭证注入调研笔记

- 调研日期：2026-10-24
- 一句话结论：**v2 kit 的正规凭证注入方式是「kit 声明 `credentials` + 宿主侧用 `sbx secret set <service>` 存值 + 用户批准 `~/.config/sbx/credentials.yaml` 里的 credential binding」；`sbx secret set-custom`（占位符替换）是另一套独立的、实验性的机制，它不会创建 binding，也替代不了 kit 声明的 gated credential service——二者不可混为一谈。**

> 来源约定：本文所有论断都标注「官方文档文件名 §小节」或「sbx 实测」。
> 官方文档文件 = 本机拉取的 docker/docs 仓库原始 markdown + docker/sbx-kits-contrib + docker/sandbox-kit-spec 规范源码。
> 「实测」= 本机 `/opt/homebrew/bin/sbx`（v0.49.1，`sbx version v0.49.1 c5b19951...`）上的实际命令输出，均已附原始输出。

---

## 核心结论（权威做法 / 推荐路径）

1. **推荐路径（v2 kit 的正规做法，官方文档明确定义）**：把凭证值作为 **service secret** 存进宿主 secret store，并批准该 service 的 **credential binding**。
   - kit 侧声明（kits-v2.md §Credentials；SPEC-v2.md §5.4/§5.4.1）：
     ```yaml
     credentials:
       - service: xhs
         apiKey:
           name: XHS_COOKIE
           proxyManaged: true
           inject:
             - domain: edith.xiaohongshu.com
               header: Cookie
               format: "%s"
     permissions:
       network:
         allow: [edith.xiaohongshu.com]
     ```
   - 宿主侧两步（credentials.md §Stored secrets + §Credential bindings）：
     1. `sbx secret set xhs`（值以 service 标识符为 key 存入宿主 keychain；自定义 kit 声明的 service 名直接可用，实测通过）；
     2. 批准 binding——交互式首次运行会自动弹出，或手写 `~/.config/sbx/credentials.yaml`：
        ```yaml
        bindings:
          xhs:
            apiKey:
              domains: [edith.xiaohongshu.com, xiaohongshu.com]
        ```
   - 效果（实测验证）：创建沙箱不再有「no binding authorizes xhs」告警；容器内 `XHS_COOKIE=proxy-managed`（哨兵值），`SBX_CRED_XHS_MODE=apikey`；代理在向 `inject[].domain` 发请求时把真实 cookie 写进 `Cookie` 头，真实值不进沙箱。

2. **`sbx secret set-custom` 是独立机制，不是 v2 kit 的凭证注入方式**：
   - 它是「以（域 + 环境变量名 + 占位符）为 key、代理做占位符→真实值替换」的机制（credentials.md §Custom secrets；`sbx secret set-custom --help` 自述 EXPERIMENTAL）。
   - 官方明确说它是给「service-identifier 模型不适用」的场景（例如 agent 在启动时校验环境变量格式）用的，并且「只要能用 service-based flow 就优先用它」（credentials.md §Custom secrets）。
   - 实测：即便 `set-custom --host edith.xiaohongshu.com --env XHS_COOKIE` 已设置，带 kit 创建沙箱**仍然打印** `no binding authorizes xhs — the credential was not injected. Create a binding (...)`。custom secret 没有 service 标识符，不写入 `credentials.yaml`，因此**不满足第三方 kit 的 binding 门槛**（credentials.md §Kits that require a binding：「Third-party kits require your approval to use credentials, regardless of schema version」）。
   - 且当 kit 对同名 env 变量声明 `proxyManaged: true` 时，容器内该变量会被覆盖成 `proxy-managed` 哨兵，占位符不再出现（实测）；只有 kit **不**设 `proxyManaged` 时占位符才保留，但 binding 告警依然存在。

3. **对 xhs-mixin 的直接结论**：若要让 kit 声明的 `service: xhs` 凭证真正生效（代理注入 Cookie 头），必须走 `sbx secret set xhs` + `credentials.yaml` binding。custom secret 那条路可以独立用于「agent 自读 env 变量并放进请求头」的形态，但前提是 kit 不要对同名变量声明 `proxyManaged: true`，且它永远替代不了 binding 授权。

---

## 问题 1：v2 kit 规范里 `credentials` 的完整结构

**答案**：`credentials` 是顶层列表，每个条目按 service 声明「需要什么凭证 + 代理在哪里、以什么形式注入」，**不声明值从哪来**（kits-v2.md §Credentials；SPEC-v2.md §5.4）。

字段（kits-v2.md §Credentials 表格；SPEC-v2.md §5.4 表格）：

| 字段 | 必需 | 含义 |
| --- | --- | --- |
| `service` | 是 | 凭证标识符，小写 kebab-case（`^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$`），与 `sbx secret set` 存的值按同一标识符匹配 |
| `description` | 否 | 批准 binding 时展示给用户 |
| `required` | 否（默认 `false`） | 标记为 agent 必需；无 binding 时 `sbx` 告警并以「凭证 withheld」启动（不失败） |
| `provider` | 否 | 保留给 provider registry；接受但告警、无运行时效果 |
| `apiKey` | 二选一或都有 | API-key 注入（见下） |
| `oauth` | 二选一或都有 | OAuth 拦截（见下） |

每个 service 必须声明 `apiKey`、`oauth` 或两者；两者都解析到时 apiKey 优先、OAuth 兜底（kits-v2.md §Credentials；SPEC-v2.md §5.4）。

`apiKey` 字段（kits-v2.md §apiKey 表格；SPEC-v2.md §5.4.1）：

| 字段 | 含义 |
| --- | --- |
| `name` | 容器内环境变量名（如 `XHS_COOKIE`）。SPEC-v2.md §5.4.1 精确语义：**仅当同时设 `proxyManaged: true` 时引擎才把该变量设为 `proxy-managed` 哨兵；只有 `name` 不设 `proxyManaged` 时，引擎在容器内不注入任何值**。v2 下空 `name` 会告警（纯代理侧处理、无容器内变量）。 |
| `proxyManaged` | `true` 时容器内 `name` 被设为 `proxy-managed` 哨兵（取代 v1 的 `environment.proxyManaged`；SPEC-v2.md §5.5）。真实值始终在宿主。 |
| `inject[].domain` | 必需；必须同时出现在 `permissions.network.allow`，否则 validate 告警、引擎加载/创建时强制校验（SPEC-v2.md §5.2、§6）。 |
| `inject[].header` | 代理写入的 HTTP 头（如 `x-api-key`、`Authorization`、`Cookie`）。 |
| `inject[].format` | 头值格式，必须恰好含一个 `%s`（如 `"%s"`、`"Bearer %s"`）。与 `scheme` 互斥。 |
| `inject[].scheme` | 常见认证方案糖：`bearer` → `Authorization: Bearer %s`；`basic` 需要 `username`。与 `format` 互斥。 |
| `inject[].username` | HTTP Basic 用户名（如 Git over HTTPS 的 `x-access-token`），不能含 `:`。 |

官方示例：SPEC-v2.md §4.4 的 `github-mixin`（scheme: bearer + scheme: basic）、§5.4.1 的 anthropic；credentials.md 的 v2 tab。

`oauth` 字段（kits-v2.md §oauth 表格；SPEC-v2.md §5.4.2）：`tokenEndpoint.host/path`、`sentinels.accessToken/refreshToken`、`credentialFile.path/structure|template`（`structure` 优先，JSON）、`resourceHosts`、`skipIfEnv`（v2 下接受但忽略）、`responseFields`、`passthrough`（放真实 token 进沙箱=安全降级）。

**证据**：
- kits-v2.md §Credentials：「A kit declares the credentials it needs and how the proxy injects them into outbound requests. It does not declare a host discovery source.」
- SPEC-v2.md §5.4：「Each entry declares **what** the kit needs and **where** to inject the resolved value. The user-side bindings file (`~/.config/sbx/credentials.yaml`) declares **where** the credential lives — kits never declare discovery.」
- SPEC-v2.md §1.2 严格解码：未识别字段是硬错误。
- 实测（最小 v2 mixin `tests/mixin-xhs/spec.yaml`）：
  ```
  $ sbx kit validate --offline tests/mixin-xhs
    ✓ /private/tmp/xhs-mixin/tests/mixin-xhs — valid (directory)
  $ sbx kit inspect --offline tests/mixin-xhs
    Name: xhs   Kind: mixin   Schema: v2
    Policies:
      Network:      1 allow, 0 deny
      Credentials:  1 sources
      Environment:  0 variables, 1 proxy-managed
  ```
  即 `proxyManaged: true` 在 inspect 里体现为「1 proxy-managed」环境变量。

---

## 问题 2：kit 声明的凭证值从哪来

**答案**：值由**用户/宿主**提供，途径按官方文档有四类（credentials.md §How credential injection works 表格）：Stored secrets、Custom secrets、OAuth、Registry credentials。对 kit 声明的 service 凭证，官方默认且推荐的是 **Stored secrets**。

- credentials.md §How credential injection works：「The kit declares the match and the header; you provide the value on the host.」「There are several ways to provide that value. When more than one source has a value for the same service, the stored secret takes precedence.」
- credentials.md §Stored secrets：「`sbx secret set` stores credential values or dynamic secret sources in your OS keychain, keyed on a service identifier. Built-in agents declare a fixed set of services. **Custom kits can declare their own. The same `sbx secret set` flow works for both.**」
- credentials.md §Services declared by kits：「Use the service identifier from the kit's documentation when storing its credential. For a kit that declares `my-service`, run: `sbx secret set my-service`. **There's no separate registration step.** The stored value and the kit's request use the same identifier.」
- 动态来源：`sbx secret set <svc> --ref 'op://…'`（1Password）或 `--ref 'arn:aws:secretsmanager:…'` / `--command 'gh auth token'`（credentials.md §Use a dynamic secret source）。
- kits-v2.md §Credentials：「The user provides the value through the secret store or the first-run prompt, and a credential binding authorizes its use. **A kit can't read arbitrary host environment variables or files.**」
- OAuth：宿主侧登录流程，token 不进沙箱（credentials.md §Stored secrets 表格、§Best practices）。
- 实测：`sbx secret set xhs` 接受自定义 service 名（不在内置列表 `anthropic, copilot, cursor, devin, droid, github, google, groq, mistral, nebius, openai, openrouter, xai` 里）：
  ```
  $ echo "dummy-xhs-cookie" | sbx secret set xhs
  Enter secret: Applied global secret to existing sandboxes
  Saved secret xhs (global)
  $ sbx secret ls
  SCOPE      TYPE      NAME   SECRET
  (global)   service   xhs    (stored)
  ```

---

## 问题 3：kit 声明的 gated credential service 与宿主机 binding（~/.config/sbx/credentials.yaml）的关系

**答案**：二者是**契约的两半**——kit 声明「需要什么、注入到哪里」；宿主机 binding 文件声明「用户批准了哪个机制、哪些域」。kit 永远不声明发现/存储位置（kits-v2.md §Credentials；SPEC-v2.md §5.4；bindings/types.go 包注释）。

- 位置与结构（credentials.md §Credential bindings；bindings/load.go 权威实现）：
  - 路径：`~/.config/sbx/credentials.yaml`（macOS/Linux，`$XDG_CONFIG_HOME` 优先），Windows 为 `%APPDATA%\sbx\credentials.yaml`。
  - 结构（bindings/types.go 权威实现）：
    ```yaml
    bindings:
      xhs:
        apiKey:
          domains: [edith.xiaohongshu.com]
        oauth:
          domains: [...]
    ```
    每个 `bindings` 条目以 **service 标识符**为 key；块的存在即「批准该机制」（`apiKey`/`oauth` 各带 `domains` 列表）；没有 `apiKey`/`oauth` 块的条目无意义；拒绝时根本不会写入条目。
- 语义（credentials.md §Credential bindings）：
  - 「Providing a value and approving its use are separate steps. Credential bindings record which mechanisms and domains you authorize a kit to use. **They don't store the credential value.**」
  - 「**Third-party kits require an approved binding for each credential they use, regardless of schema version.** `sbx` creates one interactively the first time you run such a kit; you can also write entries by hand. Credentials requested only by the built-in kits shipped with `sbx` don't need a binding.」
  - First-run approval：交互式运行会引导批准；非交互（CI / `--detach`）无人应答时，凭证 withheld、沙箱照常启动；`required` 凭证也只是告警不失败（credentials.md §First-run approval）。
- v2 专有说明：
  - SPEC-v2.md §1.3：「the engine keys its credential-binding regime on this value [schemaVersion]」——schemaVersion 行为上有意义。
  - SPEC-v2.md §8 / kits-v2.md §Schema versions 迁移表：v1 的 `credentials.sources.<id>` → v2 的 `credentials:` 列表 + binding；「Credential discovery also moved out of the kit in v2…where each value comes from is controlled by the user through credential bindings.」（kits-v2.md）
  - environment-files.md §bindings：环境文件的 `bindings` 会 merge 进全局 `credentials.yaml`，是同一个文件。
- 实测：本机初始 `~/.config/sbx/credentials.yaml` 不存在（`cat` 报 No such file or directory）。手写该文件（仅 `xhs.apiKey.domains`）+ `sbx secret set xhs` 后创建带 mixin 的沙箱：
  ```
  ✓ Created sandbox xhs-bound-probe          # 无任何 binding 告警
  $ sbx exec xhs-bound-probe -- sh -c 'echo "XHS_COOKIE=[$XHS_COOKIE]"; echo "SBX_CRED_XHS_MODE=[${SBX_CRED_XHS_MODE:-unset}]"'
  XHS_COOKIE=[proxy-managed]
  SBX_CRED_XHS_MODE=[apikey]
  ```
  运行期注入的 `SBX_CRED_<SERVICE>_MODE` 取值为 `apikey|oauth|none`，是 SPEC-v2.md §9.5 定义的运行期契约变量（「how the credential for `<SERVICE>` was resolved」，在 `setup.install` 前注入）。

---

## 问题 4：`sbx secret set-custom` 与 kit 凭证是不是两套机制？哪个才是 v2 kit 的正规做法？

**答案：是两套独立机制。v2 kit 的正规做法是 service secret + binding；`set-custom` 是面向「service 模型不适用」场景的实验性逃生通道，官方从未把它定义为 kit 凭证的注入路径。**

官方文档的分工：

- credentials.md §How credential injection works 把四种形态并列成表：Stored secrets / Custom secrets / OAuth / Registry，各自「keyed by」的对象不同——service 标识符 vs（域 + 环境变量 + 占位符）。「When more than one source has a value for the same service, the stored secret takes precedence.」
- credentials.md §Custom secrets（紧接一个 EXPERIMENTAL 警示）：
  - 「For credentials that don't fit the service-identifier model — for example, when an agent validates the environment variable format at boot — use `sbx secret set-custom`. The secret is keyed on one or more target domains, an environment variable name, and an optional placeholder string, **instead of a service identifier**.」
  - 「**Prefer the service-based flow whenever it's an option — the kit handles the wiring; you only provide the value.**」
  - 机制：容器内 env 变量被设为生成占位符（如 `sbx-cs-<rand>`）；沙箱进程向配置的 host 发请求、且占位符出现在 HTTP 请求头里时，代理替换为真实值；**替换只作用于 HTTP 请求头，不作用于请求体**。真实值不进沙箱。
- `sbx secret set-custom --help`（实测，节选）：
  ```
  EXPERIMENTAL: this command may change or be removed in future releases.
  Custom secrets work via a placeholder: the sandbox sees the placeholder value
  instead of the real secret. When the sandbox makes an outbound request to the
  target host, the proxy replaces the placeholder with the real secret in the
  request headers — the secret never enters the sandbox directly.
  ```
  flags：`--host`（可重复/通配）、`--env`、`--value`/`--token`、`--placeholder`、`--sandbox`、`--ref`/`--command`；`--header`/`--format` 仅 `--cloud` 下使用。**整个 help 没有任何关于 kit、binding、service 的字眼**。
- 官方文档**没有任何一处**把 `set-custom` 描述为「kit 声明的 gated credential 的取值来源」。binding 门槛是另一维度：任何第三方 kit 声明的 service 都需要 binding（credentials.md §Kits that require a binding），custom secret 没有 service 标识符，自然也不会创建 binding。

实测（核心证据，全部在本机复现）：

场景 A：只有 custom secret，无 binding，创建带 `proxyManaged` mixin 的沙箱：
```
$ sbx secret set-custom --host edith.xiaohongshu.com --env XHS_COOKIE --value 'web_session=TEST_COOKIE_VALUE'
Saved custom secret sbx-cs-lBQ4NcRv5OmGSVFp for target edith.xiaohongshu.com env XHS_COOKIE ((global))
Generated placeholder:  sbx-cs-lBQ4NcRv5OmGSVFp
You may need to update environment variable XHS_COOKIE inside existing sandboxes to "sbx-cs-lBQ4NcRv5OmGSVFp" ...
$ sbx create --name xhs-custom-probe shell --kit mixin-xhs ...
Note: no binding authorizes xhs — the credential was not injected. Create a binding (re-run interactively, or edit ~/.config/sbx/credentials.yaml) to use it.
  ✓ Created sandbox xhs-custom-probe
$ sbx exec xhs-custom-probe -- sh -c 'echo "XHS_COOKIE=[$XHS_COOKIE]"; echo "SBX_CRED_XHS_MODE=[${SBX_CRED_XHS_MODE:-unset}]"'
XHS_COOKIE=[proxy-managed]
SBX_CRED_XHS_MODE=[none]
```
→ custom secret 存在，但 kit 声明 `proxyManaged: true` 覆盖了同名 env 变量为哨兵；binding 告警照常。

场景 B：同一 custom secret，创建**不带** kit 的纯 shell 沙箱：
```
$ sbx create --name xhs-custom-nokit shell ...
  ✓ Created sandbox xhs-custom-nokit
$ sbx exec xhs-custom-nokit -- sh -c 'echo "XHS_COOKIE=[$XHS_COOKIE]"'
XHS_COOKIE=[sbx-cs-lBQ4NcRv5OmGSVFp]
```
→ custom secret 机制本身有效：env 变量被设为占位符。

场景 C：kit 声明 `name: XHS_COOKIE` 但**不设** `proxyManaged`，custom secret 仍在：
```
Note: no binding authorizes xhs — the credential was not injected. ...
  ✓ Created sandbox xhs-nopm-probe
$ sbx exec xhs-nopm-probe -- sh -c 'echo "XHS_COOKIE=[$XHS_COOKIE]"'
XHS_COOKIE=[sbx-cs-lBQ4NcRv5OmGSVFp]
```
→ 占位符保留（因为 kit 没设 proxyManaged），但 binding 告警依然出现（kit 声明了 service xhs 就需要 binding）。

场景 D：binding + service secret（场景 A 加回正规路径）：
```
# ~/.config/sbx/credentials.yaml:
# bindings:
#   xhs:
#     apiKey:
#       domains: [edith.xiaohongshu.com]
$ sbx secret set xhs
Saved secret xhs (global)
$ sbx create --name xhs-bound-probe shell --kit mixin-xhs ...
  ✓ Created sandbox xhs-bound-probe        # 无告警
$ sbx exec xhs-bound-probe -- ...
XHS_COOKIE=[proxy-managed]
SBX_CRED_XHS_MODE=[apikey]
```

**结论（Q4）**：
- 两套机制：`set-custom` = 以（域, env, 占位符）为 key 的**代理占位符替换**，面向 agent 自读 env/自填 header 的形态；kit `credentials` + binding + `sbx secret set <service>` = 以 **service 标识符**为 key 的**代理头注入**。
- v2 kit 的正规做法是后者；custom secret 是实验性的补充（官方：「Prefer the service-based flow whenever it's an option」）。
- 若在 kit 里声明了 `proxyManaged: true` 的同名 env 变量，custom secret 的占位符会被覆盖、且 binding 告警仍在；若想走 custom secret 路线，kit 就**不要**声明该凭证（或至少不设 `proxyManaged`），并接受「无 binding」告警（仅表示 kit 代理注入未激活，custom secret 的占位符替换仍独立工作）。

---

## 问题 5：v2 与 v3 在 secret 注入上的差异

**答案**：底层契约一致（都依赖宿主 secret store + binding 文件），但声明语法、阶段（phase）与部分细节不同。v3 是独立格式，不能与 v1/v2 组合（kits-v3.md §Version compatibility）。

| 维度 | v2（kits-v2.md；SPEC-v2.md） | v3（kits-v3.md；v3-credential-cap.md；credentials.md） |
| --- | --- | --- |
| 声明位置 | 顶层 `credentials:` 列表 | `capabilities:` 里的 `com.docker.sandbox/credential@1` 条目 + 单独的 `com.docker.sandbox/network-policy@1`（v3 凭证注入域必须进 network policy 的 allow，credentials.md v3 tab） |
| 字段 | `service`, `required`, `apiKey{name,proxyManaged,inject[]}`, `oauth{...}` | `config: {service, phase, optional, apiKey{name,proxyManaged,inject[]}, oauth{...}}` |
| 是否必需 | `required: true`（无 binding 时告警并 withheld，不失败） | `optional: true`（条目级）；`required` 无 binding 时**解析失败**（v3-credential-cap.md §Runtime behavior：required-without-binding-fails） |
| phase | 无阶段概念，运行时注入 | **`phase: [install, runtime]` 是必需的**；install-only 凭证仅在 install hook 期间可注入、entrypoint 前撤销（v3-credential-cap.md） |
| `scheme` | v2 支持 `inject[].scheme`（bearer/basic 糖） | v3 **不用** `scheme`（credentials.md：「`sbx` doesn't use `apiKey.inject[].scheme` in v3 kits」），v3 示例直接写 `header: Authorization, format: "Bearer %s"` |
| credentialFile 编码 | v2 仅 JSON（`structure` 优先于 `template`） | v3 支持 `credentialFile.format: json|toml`（v3-credential-cap.md） |
| SSH agent | v2 默认转发（credentials.md §SSH agent） | v3 必须显式请求 `ssh-agent@1` capability |
| 注入-only 凭证 | v2 空 `name` 仅告警（纯代理侧） | v3 无 `name` + 有 `inject` = 注入-only，**容器内零 env 存在（连哨兵都不设）**（v3-credential-cap.md） |
| binding 要求 | 第三方 kit 需 binding | 同样需要（credentials.md §Kits that require a binding：「regardless of schema version」） |
| 哨兵 | `proxyManaged: true` → env = `proxy-managed` | 同样（named+proxyManaged → sentinel；inject-only 无 env 存在） |

共同点：两者都「MUST resolve the credential from the host-side store keyed by `service`；host env vars never auto-inject；a Kit cannot name where a secret lives, only what it needs」（v3-credential-cap.md §Runtime behavior；对应 v2 的 kits-v2.md §Credentials）。schemaVersion "2" 仍是内置 agent（claude/codex）默认格式，v2 不被弃用（kits-v2.md；kits-v3.md）。

---

## 问题 6：本机 sbx 实测记录（v0.49.1）

1. `sbx version` → `sbx version v0.49.1 c5b19951af121b439800029695f88bf1139a0b0b`（daemon 同版本，`sbx inspect` 显示 Daemon: v0.49.1）。
2. `sbx secret set-custom --help`：见问题 4（EXPERIMENTAL、占位符替换、--host/--env/--value/--placeholder/--sandbox；--header/--format 仅 --cloud）。
3. `sbx secret set --help`：内置服务列表 + service secret 存 keychain + --oauth/--ref/--command/--registry 子模式；「When SERVICE is omitted, an interactive prompt selects it」。
4. `sbx secret set xhs`：接受自定义 service（实测通过，见问题 2）。
5. `sbx secret ls`：两种输出节——service secrets（`SCOPE TYPE NAME SECRET`）与 `CUSTOM SECRETS`（`SCOPE TARGETS ENV PLACEHOLDER SECRET`），二者分区显示，印证两套机制。
6. `sbx kit validate --offline` / `sbx kit inspect --offline`：最小 v2 mixin（含 `credentials[].apiKey`）→ valid；`Credentials: 1 sources`、`Environment: 0 variables, 1 proxy-managed`。
7. `sbx kit validate --offline` 对「inject 域不在 network allow」的变体：
   ```
   warning: apiKey inject domain not covered by permissions.network.allow: credentials[0] (service "xhs") inject[0].domain "edith.xiaohongshu.com"
     ✓ ... — valid (directory)     # exit 0，仅告警
   ```
   （与 SPEC-v2.md §6 一致：validate 只告警，引擎在加载/创建时强制。）
8. `sbx create shell --kit tests/mixin-xhs`（无 binding）→ 复现告警原句：
   ```
   Note: no binding authorizes xhs — the credential was not injected. Create a binding (re-run interactively, or edit ~/.config/sbx/credentials.yaml) to use it.
     ✓ Created sandbox ...
   ```
9. 场景 A–D 的 env 对比见问题 4：`proxy-managed` 哨兵 vs `sbx-cs-…` 占位符 vs `SBX_CRED_XHS_MODE` 的 `apikey|none`。
10. 清理：所有探针沙箱（xhs-mixin-probe / xhs-custom-probe / xhs-custom-nokit / xhs-nopm-probe / xhs-bound-probe）已删除，测试用 custom secret（placeholder sbx-cs-lBQ4NcRv5OmGSVFp）与测试 service secret（xhs）已删除，`~/.config/sbx/` 目录已恢复原状（不存在）。预先存在的 custom secret（`ark.cn-beijing.volces.com / ANTHROPIC_AUTH_TOKEN`）未触碰。

---

## 已知观察核验

任务里给出的三条「已知实测观察」核验结果：

1. 「v2 mixin 用 `credentials: - service: xhs / apiKey: {name: XHS_COOKIE, proxyManaged: true, inject: [{domain…, header: Cookie, format: "%s"}]}` 能通过 validate」——**属实**（实测 `sbx kit validate --offline` exit 0）。
2. 「宿主 `sbx secret set-custom --host <域> --env XHS_COOKIE --value <cookie>` 会把容器 env XHS_COOKIE 设为占位符（sbx-cs-xxx），proxy 在发往 --host 域的请求上做占位符→真实替换」——**对，但仅在 kit 未对该 env 变量声明 `proxyManaged: true` 时成立**（场景 B/C）；kit 声明了 proxyManaged 时 env 是 `proxy-managed` 哨兵（场景 A）。占位符→真实替换只作用于 HTTP 请求头（credentials.md §Custom secrets）。
3. 「即使设了 custom secret，创建沙箱仍可能打印 `no binding authorizes xhs — the credential was not injected. …`」——**属实且可稳定复现**（场景 A/C）。原因：custom secret 无 service 标识符、不写 `credentials.yaml`，第三方 kit 声明的 service 仍需 binding（credentials.md §Kits that require a binding）。

「结论倾向：custom secret 与 kit 声明的 gated credential service 是两套机制」——**官方文档与实测一致支持**：见问题 4。

---

## 一手来源清单（均为本机拉取的官方原始文档 / 规范源码 / 实测输出）

- `docker/docs` 仓库（default branch: main）：
  - `content/manuals/ai/sandboxes/customize/kits-v2.md`（本地 `/private/tmp/kits-v2.md`，docker/docs sha 6d83f41fa451df7c086eca6c840ea0bd5c2b91dc）
  - `content/manuals/ai/sandboxes/customize/_index.md`（v3，本地 `/private/tmp/kits-v3.md`）
  - `content/manuals/ai/sandboxes/customize/use-kits.md`（`/private/tmp/use-kits.md`）
  - `content/manuals/ai/sandboxes/configuration/credentials.md`（`/private/tmp/ghdocs/credentials.md`）
  - `content/manuals/ai/sandboxes/configuration/environment-files.md`（`/private/tmp/ghdocs/environment-files.md`）
  - `content/manuals/agentic-platform/{secrets,sandboxes,mcp,kits}.md`（`/private/tmp/agentic-*.md`，Docker Agentic Platform 云控制台产品线，仅作旁证，不是本地 sbx 的机制来源）
- `docker/sbx-kits-contrib` 仓库（v2 规范权威实现）：
  - `spec/SPEC-v2.md`（`/private/tmp/ghdocs/SPEC-v2.md`，§5.4/§5.4.1/§5.4.2/§6/§9.5）
  - `spec/bindings/{types,load,validate}.go`（`/private/tmp/ghdocs/bindings-*.go`，credentials.yaml 格式权威定义）
- `docker/sandbox-kit-spec` 仓库：
  - `docs/spec/capabilities/com.docker.sandbox/credential@1.md`（`/private/tmp/ghdocs/v3-credential-cap.md`）
- 本机 sbx CLI v0.49.1 实测（探针目录 `/private/tmp/xhs-mixin/tests/`：`mixin-xhs/`、`mixin-xhs-nopm/`、`mixin-xhs-warn/` 与 `create-probe*.log`）。
