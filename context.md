# Xiaohongshu (小红书) Query — MCP Tools Guide

This sandbox is extended by the `xhs-query` mixin. Use the **xhs-mcp** MCP server
to query Xiaohongshu. All tools are namespaced under the `xhs-mcp` server. The MCP
server config comes from the workspace-root `.mcp.json` (claude reads this file from
the workspace root; the old `.mcp/` directory form is not auto-discovered).

## Available MCP tools
| Tool | Purpose | Args |
|------|---------|------|
| `xhs_search_note` | Search notes by keyword | `keyword` (required), `browser_path` (optional) |
| `xhs_get_note_detail` | Get a note's full detail by id | `feed_id` (required), `xsec_token` (required), `browser_path` (optional) |
| `xhs_discover_feeds` | Discover recommended feeds | `browser_path` (optional) |
| `xhs_auth_login` | Log in to Xiaohongshu (opens a browser to scan the app QR code) | `browser_path` (optional) |
| `xhs_auth_logout` | Log out / clear saved cookies | — |
| `xhs_auth_status` | Check current login status | — |

## Authentication
- xhs-mcp is a **browser-automation** server: it drives a headless Chromium against
  `www.xiaohongshu.com` and reads the page's `__INITIAL_STATE__` data. Login state is
  read only from `~/.xhs-mcp/cookies.json` (appDataDir = `~/.xhs-mcp`). It does **not**
  read the `XHS_COOKIE` environment variable directly, and no tool accepts a cookie
  argument.
- **Baked cookie + auto-install (primary path)**: the xhs-query mixin ships a
  sanitizable copy of the cookie bundle at the workspace root as
  `xhs-cookies.json` (it is dropped there automatically on every sandbox create).
  The workspace-root `.mcp.json` wraps the xhs-mcp server command so that the
  provided sanitizer runs first, on every sandbox load, with **zero manual steps**:
  `sh xhs-install-cookie.sh` reads `./xhs-cookies.json`, omits `expires` for
  session cookies, truncates float `expirationDate` to int `expires`, writes
  `~/.xhs-mcp/cookies.json`, and prints a masked confirmation (suppressed during
  the auto-run so it doesn't pollute the MCP stdio stream). Re-run it manually at
  any time: `sh xhs-install-cookie.sh [cookie-file]` (or `XHS_COOKIE='[…]'` as an
  alternate source — an explicit file argument and `$XHS_COOKIE` take priority
  over the baked file).
- **In-sandbox login (alternative)**: call `xhs_auth_login` (or run
  `npx xhs-mcp login` in the sandbox) to open a browser and scan the QR code with the
  Xiaohongshu app on your phone; the login state is written to
  `~/.xhs-mcp/cookies.json`. `*.xiaohongshu.com` is on the network allowlist, so it is
  reachable from the sandbox.
- **Host injection (optional path)**: if the host's `~/.config/sbx/credentials.yaml`
  has a binding for service `xhs`, the sandbox egress proxy injects the Cookie header
  into allowlisted-domain requests — but this path is untested for browser traffic, so
  prefer the baked-cookie path above.
- **Expiry**: cookies expire (401/461/anti-crawl). When that happens, refresh the
  baked file on the host (`~/Downloads/www.xiaohongshu.com_json_*.json` → copy to the
  kit's `files/workspace/xhs-cookies.json`, which also updates every future sandbox),
  or re-run `xhs_auth_login`.

## Behavior notes
- `xhs_get_note_detail` needs the note's `xsec_token` (required arg, obtained from
  search results or share links).
- Respect rate limits: avoid bursting the search/detail endpoints; Xiaohongshu
  aggressively rate-limits and fingerprints automated clients.
- Purely read-only usage is intended. Do not publish/delete/comment unless asked.
