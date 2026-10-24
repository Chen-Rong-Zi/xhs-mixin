# Xiaohongshu (小红书) Query — MCP Tools Guide

This sandbox is extended by the `xhs-query` mixin. Use the **xhs-mcp** MCP server
to query Xiaohongshu. All tools are namespaced under the `xhs-mcp` server. The MCP
server config comes from the workspace-root `.mcp.json` (claude reads this file from
the workspace root; the old `.mcp/` directory form is not auto-discovered).

The server is **jobsonlook/xhs-mcp** — a signed-API MCP server (JS-reversed
`x-s`/`x-t` headers), vendored and patched in the kit at `./xhs-mcp-src/` and run
with `uv run --project ./xhs-mcp-src python -m xhs_mcp`. Patches vs upstream:
(a) `search_notes` gained a `count` argument with page-by-page collection (fetch a
specified number of posts); (b) cookie resolution falls back to
`~/.xhs-mcp/cookies.json`; (c) `mcp` pinned `<2` (upstream breaks under mcp 2.x).

## Available MCP tools
| Tool | Purpose | Args |
|------|---------|------|
| `search_notes` | Search notes by keyword, **fetch up to `count` posts** (paginates) | `keywords` (required), `count` (optional, default 20) |
| `get_note_content` | Get a note's full detail (title/author/time/likes/comments/collected/desc/cover) | `url` (required, must include `xsec_token`) |
| `get_note_comments` | Get a note's comments | `url` (required, must include `xsec_token`) |
| `home_feed` | Get recommended feed notes | — |
| `check_cookie` | Check whether the saved cookie is valid | — |
| `post_comment` | Post a comment to a note | `note_id`, `comment` (use with care) |

There are **no** `xhs_auth_*` login tools in this server — authentication is
cookie-only (see below). Tool names differ from the previous server: search is
`search_notes` (was `xhs_search_note`), detail is `get_note_content` (was
`xhs_get_note_detail`), feed is `home_feed` (was `xhs_discover_feeds`).

## Fetching a specified number of posts
`search_notes(keywords="上海 租房", count=50)` returns up to 50 notes: the tool
loops the search API page by page (page_size 20) until it has collected `count`
results or the API returns no more. This is the capability the rent-room crawler
needs — the upstream tool only returned a fixed single page (20 items, page 1);
the vendored copy adds `count`.

## Authentication
- This server reads the cookie from the `XHS_COOKIE` environment variable (a
  cookie-header string like `a1=…; webId=…; web_session=…`). The vendored copy
  **falls back to `~/.xhs-mcp/cookies.json`** when `XHS_COOKIE` is unset or is the
  sbx sentinel `proxy-managed`, so the mixin's existing cookie auto-install keeps
  working unchanged.
- **Baked cookie + auto-install (primary path)**: the xhs-query mixin ships a
  sanitizable copy of the cookie bundle at the workspace root as `xhs-cookies.json`
  (dropped there automatically on every sandbox create). The workspace-root
  `.mcp.json` wraps the server command so the provided sanitizer runs first, on
  every sandbox load, with **zero manual steps**: `sh xhs-install-cookie.sh` reads
  `./xhs-cookies.json`, sanitizes it, writes `~/.xhs-mcp/cookies.json`, and prints
  a masked confirmation (suppressed during the auto-run so it doesn't pollute the
  MCP stdio stream). Re-run it manually at any time:
  `sh xhs-install-cookie.sh [cookie-file]`.
- **Host injection (optional path)**: if the host's `~/.config/sbx/credentials.yaml`
  has a binding for service `xhs`, the sandbox egress proxy injects the Cookie
  header into allowlisted-domain requests — but prefer the baked-cookie path above.
- **Expiry**: cookies expire (401/461/-100). Refresh the baked file on the host
  (`~/Downloads/www.xiaohongshu.com_json_*.json` → copy to the kit's
  `files/workspace/xhs-cookies.json`), or re-export a fresh cookie header string.

## Direct egress requirement (browser + signed API)
jobsonlook/xhs-mcp signs its API requests by loading `www.xiaohongshu.com/explore`
in a headless browser and reusing the page's signing runtime (`_webmsxyw`) to
compute `X-S`/`X-T`/`X-S-Common`. The sbx MITM proxy (`gateway.docker.internal:3128`)
TLS-re-originates traffic, so Xiaohongshu sees a non-Chrome fingerprint and flags
the session (`user/me` → `code=-100/-101`, search → `461`, page → redirect to
`website-login/error?error_code=300012 IP存在风险`). This is fixed by the
workspace-root `.mcp.json` setting `env.NO_PROXY=*` (and lowercase `no_proxy`) for
the server process — the browser is a child process and inherits it, so it connects
**directly** to `*.xiaohongshu.com` / `*.xhscdn.com` (both on the network allowlist).
Keep this env; it is required for the signed API + browser to work.

## Behavior notes
- **XHS risk control**: the API aggressively rate-limits and fingerprints. A burst
  of calls can trip 461 and then invalidate the session (`-100 登录已过期`) or flag
  the egress IP (`300012`). Space requests out; after a flag, wait minutes before
  retrying.
- `get_note_content` / `get_note_comments` need a full note URL **with its
  `xsec_token`** (obtained from `search_notes` results or share links).
- Purely read-only usage is intended. Do not publish/comment unless asked.
- Image prerequisite: this server needs Playwright + a Chromium browser. The
  `claude:full` image has Python 3.12+ and `uv` but **no browser** — run
  `python -m playwright install chromium` (and `install-deps chromium`) once, or
  bake it into the image (see README / Dockerfile).
