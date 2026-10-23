# Xiaohongshu (小红书) Query — MCP Tools Guide

This sandbox is extended by the `xhs-query` mixin. Use the **xhs-mcp** MCP server
to query Xiaohongshu. All tools are namespaced under the `xhs-mcp` server.

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
  read the `XHS_COOKIE` environment variable, and no tool accepts a cookie argument.
- In this container, `XHS_COOKIE` is only a **placeholder** for the host secret
  (informational). Do not treat it as a credential for xhs-mcp.
- **In-sandbox login (recommended path)**: call `xhs_auth_login` (or run
  `npx xhs-mcp login` in the sandbox) to open a browser and scan the QR code with the
  Xiaohongshu app on your phone. The login state is written to the sandbox's
  `~/.xhs-mcp/cookies.json`. `www.xiaohongshu.com` is on the network allowlist, so it is
  reachable from the sandbox.
- **Host injection (optional path)**: if the host's `~/.config/sbx/credentials.yaml`
  has a binding for service `xhs`, the sandbox egress proxy injects the Cookie header
  into allowlisted-domain requests — but this path is untested for browser traffic, so
  prefer in-sandbox login.
- **Expiry**: cookies expire (401/461/anti-crawl). When that happens, re-run
  `xhs_auth_login` to refresh the login state.

## Behavior notes
- `xhs_get_note_detail` needs the note's `xsec_token` (required arg, obtained from
  search results or share links).
- Respect rate limits: avoid bursting the search/detail endpoints; Xiaohongshu
  aggressively rate-limits and fingerprints automated clients.
- Purely read-only usage is intended. Do not publish/delete/comment unless asked.
