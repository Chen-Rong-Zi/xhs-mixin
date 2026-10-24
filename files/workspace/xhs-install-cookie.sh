#!/usr/bin/env bash
# xhs-install-cookie.sh — install the Xiaohongshu cookie bundle into xhs-mcp's
# cookie store (~/.xhs-mcp/cookies.json), sanitizing Chrome-export cookie JSON.
#
# Source resolution (first match wins):
#   (a) a path argument pointing at the Chrome-export JSON array file
#   (b) the $XHS_COOKIE environment variable (the full cookie JSON ARRAY)
#   (c) the baked file ./xhs-cookies.json — shipped inside the xhs-query mixin
#       and dropped at the workspace root on every sandbox create, so a fresh
#       sandbox gets the cookie with NO --env and NO manual step.
#
# NOTE on (b): the sbx proxyManaged credential (service: xhs, apiKey
# XHS_COOKIE) injects a SENTINEL value ("proxy-managed") into the sandbox env,
# NOT the real bundle. So an env var that doesn't parse as a JSON array is
# IGNORED and we fall through to the baked file instead of failing.
#
# Chrome export format per cookie:
#   {name, value, domain, path, expirationDate, httpOnly, secure, sameSite,
#    hostOnly, session, storeId, ...}
# xhs-mcp (Puppeteer) needs:
#   {name, value, domain, path, httpOnly, secure, expires?, sameSite?}
#
# Sanitization rules (the reason this script exists):
#   * session cookies (no expirationDate / expires<=0) -> OMIT "expires".
#     Puppeteer's setCookie rejects expires:-1 (or 0) and fails the WHOLE
#     batch, leaving xhs-mcp silently logged out.
#   * persistent cookies -> "expires" = floor(expirationDate) (truncate the
#     float epoch seconds Chrome exports to the integer Puppeteer wants).
#   * drop keys Puppeteer rejects (expirationDate, hostOnly, session, storeId)
#     and normalize sameSite (only Strict/Lax/None; drop "unspecified").
#
# Usage (inside the sandbox, workspace mounted at ~):
#   sh xhs-install-cookie.sh                              # uses baked ./xhs-cookies.json
#   sh xhs-install-cookie.sh /path/to/cookies.json        # explicit file
#   XHS_COOKIE='[...]' sh xhs-install-cookie.sh           # from env
# (invoke with `sh` — the sandbox overlay may strip the executable bit).
#
# Auto-install: the workspace-root .mcp.json wraps the xhs-mcp server command as
# `sh -c "sh xhs-install-cookie.sh >/dev/null 2>&1; exec npx xhs-mcp mcp"` with
# cwd = the workspace root, so this script runs automatically on every sandbox
# load before the MCP server starts — zero manual steps.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found — this sandbox image lacks jq." >&2
  exit 1
fi

# --- resolve the cookie source (a) arg > (b) env > (c) baked file -----------
src_file=""
cookie_json=""
if [ "$#" -ge 1 ]; then
  if [ -f "$1" ]; then
    src_file="$1"
    cookie_json="$(cat "$src_file")"
  else
    echo "ERROR: cookie file argument not found: $1" >&2
    exit 1
  fi
elif [ -n "${XHS_COOKIE:-}" ]; then
  cookie_json="$XHS_COOKIE"
  if ! printf '%s' "$cookie_json" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    # env holds the proxy-managed sentinel (or garbage) — not a real bundle.
    cookie_json=""
  fi
fi
if [ -z "$cookie_json" ] && [ -f ./xhs-cookies.json ]; then
  src_file=./xhs-cookies.json
  cookie_json="$(cat "$src_file")"
fi

# Validate the bundle parses as a non-empty JSON array.
if [ -z "$cookie_json" ] || ! printf '%s' "$cookie_json" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
  echo "ERROR: no usable cookie source. Pass a file path, set XHS_COOKIE to a real" >&2
  echo "       cookie bundle, or ensure the baked ./xhs-cookies.json is in the" >&2
  echo "       workspace root." >&2
  exit 1
fi

mkdir -p "$HOME/.xhs-mcp"

printf '%s' "$cookie_json" | jq -c '
  [
    .[] |
    ( ((.expirationDate // .expires) // 0) | floor ) as $exp |
    ( (.sameSite // "") | ascii_downcase ) as $ss |
    {
      name,
      value,
      domain,
      path,
      httpOnly,
      secure,
      expires: (if $exp > 0 then $exp else null end),
      sameSite: ( if $ss == "strict" then "Strict"
                  elif $ss == "lax" then "Lax"
                  elif $ss == "none" then "None"
                  else null end )
    } |
    with_entries(select(.value != null))
  ]
' > "$HOME/.xhs-mcp/cookies.json"

saved=$(jq 'length' "$HOME/.xhs-mcp/cookies.json")
session=$(jq '[.[] | select(has("expires") | not)] | length' "$HOME/.xhs-mcp/cookies.json")
persist=$(jq '[.[] | select(has("expires"))] | length' "$HOME/.xhs-mcp/cookies.json")

echo "Installed $saved cookies -> $HOME/.xhs-mcp/cookies.json"
echo "  persistent: $persist | session (no expires): $session"
echo "  cookies (value masked to first 8 chars):"
printf '%s' "$cookie_json" | jq -r '
  .[] |
  "    \(.name) = \(.value[0:8])…  expires: " +
  ( if ((.expirationDate // .expires) // 0 | floor) > 0
    then (((.expirationDate // .expires) | floor) | tostring)
    else "session" end )
'
