# Xiaohongshu (小红书) Query — MCP Tools Guide

This sandbox is extended by the `xhs-query` mixin. Use the **xhs-mcp** MCP server
to query Xiaohongshu. All tools are namespaced under the `xhs-mcp` server.

## Available MCP tools
| Tool | Purpose |
|------|---------|
| `xhs_search_note` | Search notes by keyword. Args: keyword, page, page_size, sort, note_type, cookie |
| `xhs_get_note_detail` | Get a note's full detail (title, desc, images, likes, comments…) by id. Args: note_id, cookie, is_xsec_req |
| `xhs_discover_feeds` | Discover recommended feeds. Args: page, page_size, cookie |

## Authentication
- The sandbox proxy injects the **Cookie** header to `edith.xiaohongshu.com` and
  `xiaohongshu.com` automatically.
- In the container, `XHS_COOKIE` holds a **placeholder** value, not the real cookie:
  the real cookie lives only in the host's secret store, and the proxy swaps the
  placeholder for the real cookie in outbound request headers to the allowlisted
  domains. `.mcp/xhs-mcp.json`'s `env.XHS_COOKIE: "${XHS_COOKIE}"` is interpolated by
  claude into that placeholder — do not treat the env var as the credential.
- The cookie comes from a real logged-in Xiaohongshu account (web login). It is
  **short-lived and bound to device fingerprint** — if calls start failing with
  461/460/anti-spam errors, refresh it on the host (re-run `sbx secret set-custom`
  with a fresh cookie) and re-provision the credential.

## Behavior notes
- `xhs_get_note_detail` with `is_xsec_req: true` needs the note's `xsec_token`.
- Respect rate limits: avoid bursting the search/detail endpoints; Xiaohongshu
  aggressively rate-limits and fingerprints automated clients.
- Purely read-only usage is intended. Do not publish/delete/comment unless asked.
