#!/usr/bin/env bash
# Restore Todoist, Lyrics, and Yoink under VirtuosoBar.
#
# Why: a replacement bar hands widgets a service-less shell facade (Omarchy
# security design), so bar.shell.serviceFor() is null and service-backed
# widgets lose their service — Todoist's panel never opens and clicks do
# nothing. This patches the three widgets to fall back to a local Service
# that drives the panel only. Stock bar behavior is unchanged (the lookup
# wins there, no fallback is made). Plugin code hot-reloads on save.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$HOME/.config/omarchy/plugins"

targets=()
for p in crmne.todoist crmne.lyrics denis.yoink; do
  f="$PLUGINS/$p/BarWidget.qml"
  if [[ -f $f ]]; then targets+=("$f"); else echo "skip: $p not installed"; fi
done
(( ${#targets[@]} )) || { echo "nothing to patch"; exit 0; }

python3 "$SRC/lib/patch-service-widget.py" "${targets[@]}"

if command -v qmlformat >/dev/null; then
  for f in "${targets[@]}"; do qmlformat "$f" >/dev/null && echo "format OK: $f"; done
fi

echo ""
echo "Done. The bar picks the fix up on its own (no restart needed)."
echo "If a widget still misbehaves: omarchy restart shell"
echo "To undo: restore the BarWidget.qml.bak.virtuoso backup next to each file."
