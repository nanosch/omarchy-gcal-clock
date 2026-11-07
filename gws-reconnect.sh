#!/bin/bash
# Re-authenticates the gws CLI for the clock's calendar agenda.
# Re-requests the same scopes the previous login had, so other gws uses
# (Gmail, Drive, …) keep working; falls back to a sensible service set.
scopes=$(gws auth status 2>/dev/null | jq -r '(.scopes // []) | map(select(startswith("https://"))) | join(",")' 2>/dev/null)

echo "Reconnecting Google (gws) — a browser window will open."
echo
if [[ -n $scopes ]]; then
  gws auth login --scopes "$scopes"
else
  gws auth login -s calendar,gmail,drive,docs,sheets,meet
fi
