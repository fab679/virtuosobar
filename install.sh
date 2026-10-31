#!/bin/bash
# VirtuosoBar installer: V2-style notch bar + VIRTUOSO wordmark.
# Your layout, widgets, and settings are untouched apart from swapping the
# menu button for the wordmark (same actions, same position).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

fail() { echo "install: $*" >&2; exit 1; }

[[ -f $SHELL_JSON ]] || fail "no shell.json at $SHELL_JSON (is this Omarchy Quattro?)"
command -v omarchy >/dev/null || fail "omarchy CLI not found"
command -v jq >/dev/null || fail "jq not found"

# Every plugin this installer ships, in validation order. Folders missing
# from the project (an unfinished widget, say) are skipped with a note.
PLUGINS_LIST="virtuoso.bar virtuoso.menu virtuoso.theme-name virtuoso.workspaces virtuoso.wave virtuoso.clock virtuoso.stream virtuoso.reactor virtuoso.gauges virtuoso.settings"

echo "==> Ensuring dependencies"
# cava feeds the Wave spectrum; idempotent, so a machine that has it skips by.
omarchy pkg add cava || echo "    WARNING: cava not installed; the Wave widget still shows transport controls"

echo "==> Validating plugins"
for id in $PLUGINS_LIST; do
  [[ -d $SRC/$id ]] || { echo "    skipping $id (not in project)"; continue; }
  omarchy plugin validate "$SRC/$id" || fail "$id failed validation"
done

echo "==> Installing to $PLUGINS"
mkdir -p "$PLUGINS"
for id in $PLUGINS_LIST; do
  [[ -d $SRC/$id ]] || continue
  rm -rf "$PLUGINS/$id" "$PLUGINS/virtuoso.hearth" "$PLUGINS/virtuoso.theme-strip"
  cp -a "$SRC/$id" "$PLUGINS/"
done

echo "==> Rescanning shell plugins"
rescan_out=$(omarchy-shell shell rescanPlugins 2>&1) || true
if echo "$rescan_out" | grep -qi "not responding"; then
  echo "WARNING: the shell did not respond to rescan. Fix it first, then re-run install:" >&2
  echo "  omarchy restart shell" >&2
  exit 1
fi
for id in $PLUGINS_LIST; do
  [[ -d $SRC/$id ]] || continue
  discovered=0
  for ((attempt = 0; attempt < 40; attempt++)); do
    if omarchy-plugin-list --json 2>/dev/null | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
      discovered=1
      break
    fi
    sleep 0.05
  done
  ((discovered)) || fail "plugin '$id' was not discovered after rescan"
done

echo "==> Installing the virtuoso-style CLI (bar looks from the menu and shell)"
mkdir -p "$HOME/.local/bin"
cp "$SRC/virtuoso.settings/scripts/virtuoso-style.sh" "$HOME/.local/bin/virtuoso-style"
chmod +x "$HOME/.local/bin/virtuoso-style"

echo "==> Installing the Bar menu (skipped if you already have one)"
if [[ -f $HOME/.config/omarchy/extensions/omarchy-menu.jsonc ]]; then
  echo "    you already have omarchy-menu.jsonc; merge the bar.* rows from $SRC/menu/ if you want them"
else
  mkdir -p "$HOME/.config/omarchy/extensions"
  cp "$SRC/menu/omarchy-menu.jsonc" "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
fi

echo "==> Backing up shell.json"
backup="$SHELL_JSON.bak.virtuoso.$(date +%s)"
cp "$SHELL_JSON" "$backup"
echo "    $backup"

echo "==> Swapping menu button for VIRTUOSO wordmark (same position)"
tmp=$(mktemp)
jq -f "$SRC/lib/install-menu-swap.jq" "$SHELL_JSON" >"$tmp"
mv "$tmp" "$SHELL_JSON"

echo "==> Swapping workspaces for glow workspaces (same position)"
tmp=$(mktemp)
jq -f "$SRC/lib/install-workspace-swap.jq" "$SHELL_JSON" >"$tmp"
mv "$tmp" "$SHELL_JSON"

echo "==> Placing theme name at the end of the left section"
tmp=$(mktemp)
jq -f "$SRC/lib/install-placement.jq" "$SHELL_JSON" >"$tmp"
mv "$tmp" "$SHELL_JSON"

echo "==> Moving Vitals to the end of the left section"
tmp=$(mktemp)
jq -f "$SRC/lib/install-vitals-left.jq" "$SHELL_JSON" >"$tmp"
mv "$tmp" "$SHELL_JSON"

echo "==> Placing spectrum transport after Lyrics in centerEnd"
tmp=$(mktemp)
jq -f "$SRC/lib/install-wave-place.jq" "$SHELL_JSON" >"$tmp"
mv "$tmp" "$SHELL_JSON"

echo "==> Wiring the sci-fi widgets (segment clock, stream, reactor, gauges, settings)"
tmp=$(mktemp)
jq -f "$SRC/lib/install-sci-fi.jq" "$SHELL_JSON" >"$tmp"
mv "$tmp" "$SHELL_JSON"

echo "==> Dropping retired standalone Hearth button, if present"
tmp=$(mktemp)
jq -f "$SRC/lib/install-cleanup.jq" "$SHELL_JSON" >"$tmp"
mv "$tmp" "$SHELL_JSON"

echo "==> Activating VirtuosoBar (layout untouched)"
omarchy bar use virtuoso.bar

echo ""
echo "Done. VirtuosoBar notch is active with the VIRTUOSO wordmark."
echo ""
echo "To bring it all live, run:"
echo "  ./fix-services.sh          (Todoist/Lyrics/Yoink click fix)"
echo "  ./wordmark.sh set <text>   (custom left mark, e.g. ./wordmark.sh set omarchy)"
echo "  omarchy pkg add cava       (animated spectrum bars; transport works without it)"
echo ""
echo "  Try shapes : ./style.sh fit | ./style.sh dock | ./style.sh notch"
echo "  Dividers   : ./style.sh dividers off   (back on with: ./style.sh dividers on)"
echo "  True blur  : omarchy bar background glassy   (frosted notch)"
echo "  No terminal: click the gear on the bar (Virtuoso Settings) — surface, effects,"
echo "               workspace pill styles, all from a panel"
echo "  Way back   : omarchy bar reset               (stock bar, same layout)"
echo "  Uninstall  : ./uninstall.sh                  (also restores menu button and clock)"
