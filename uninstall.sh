#!/bin/bash
# Remove VirtuosoBar: stock bar back, menu button restored, files removed.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

echo "==> Returning to the stock bar"
omarchy bar reset || true

if [[ -f $SHELL_JSON ]]; then
  echo "==> Restoring stock menu button and removing theme name"
  tmp=$(mktemp)
  if jq -f "$SRC/lib/uninstall-restore.jq" "$SHELL_JSON" >"$tmp"; then
    mv "$tmp" "$SHELL_JSON"
  else
    echo "WARNING: layout restore edit failed; shell.json left untouched" >&2
  fi
  if jq -e '[.bar.layout[][]? | select((if type == "object" then .id else . end) == "omarchy.menu")] | length == 1' "$SHELL_JSON" >/dev/null; then
    echo "    menu button verified back on the bar"
  else
    echo "WARNING: omarchy.menu is not exactly-once in $SHELL_JSON; restore from a shell.json.bak.virtuoso.* backup" >&2
  fi
fi

echo "==> Removing plugin files"
rm -rf "$PLUGINS/virtuoso.bar" "$PLUGINS/virtuoso.menu" "$PLUGINS/virtuoso.theme-name" "$PLUGINS/virtuoso.workspaces" "$PLUGINS/virtuoso.wave" "$PLUGINS/virtuoso.clock" "$PLUGINS/virtuoso.stream" "$PLUGINS/virtuoso.reactor" "$PLUGINS/virtuoso.gauges" "$PLUGINS/virtuoso.settings" "$PLUGINS/virtuoso.hearth" "$PLUGINS/virtuoso.theme-strip"
rescan_out=$(omarchy-shell shell rescanPlugins 2>&1) || true
if echo "$rescan_out" | grep -qi "not responding"; then
  echo "WARNING: the shell did not respond to rescan. Your config on disk is" >&2
  echo "already restored, but the visible bar is stale until you run:" >&2
  echo "  omarchy restart shell" >&2
fi

echo "Done. Stock bar and menu button restored; shell.json backups untouched."
