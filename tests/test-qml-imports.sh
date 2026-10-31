#!/bin/bash
# Static import check for VirtuosoBar QML: every Omarchy/Quickshell symbol a
# file uses must have its module imported, or the whole widget fails to load
# ("X is not a type") and silently vanishes from the bar. Run:
# ./tests/test-qml-imports.sh   (needs only grep; touches nothing)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0

# Parallel arrays: FILES[i] selects files, SYMS[i] triggers, NEEDED[i] must match.
FILES=(
  'BarWidget.qml|Panel.qml'
  'BarWidget.qml|Panel.qml'
  'BarWidget.qml|Panel.qml'
  'BarWidget.qml|Panel.qml'
  'BarWidget.qml'
  'BarWidget.qml|Panel.qml|Bar.qml'
  'Bar.qml'
  'Bar.qml'
  'BarWidget.qml|Panel.qml|Bar.qml'
  'BarWidget.qml|Panel.qml|Bar.qml'
)
SYMS=(
  'ShellIpc'
  'Commons\.'
  'FileView|Process|StdioCollector|SplitParser'
  'BarWidget|WidgetButton|BarIconButton|KeyboardPanel|PanelKeyCatcher|PanelSlider|Button'
  'Mpris'
  'ShapePath|PathMove|PathLine|PathArc'
  'MultiEffect'
  'Pipewire|PwNodePeakMonitor'
  '(^|[^.A-Za-z0-9_])Style\.'
  'RowLayout|ColumnLayout|GridLayout|Layout\.'
)
NEEDED=(
  '^import qs\.Commons$'
  '^import qs\.Commons as Commons'
  '^import Quickshell\.Io'
  '^import qs\.Ui'
  '^import Quickshell\.Services\.Mpris'
  '^import QtQuick\.Shapes'
  '^import QtQuick\.Effects'
  '^import Quickshell\.Services\.Pipewire'
  '^import qs\.Commons$'
  '^import QtQuick\.Layouts'
)

for i in "${!FILES[@]}"; do
  while IFS= read -r -d '' file; do
    if grep -qE "${SYMS[$i]}" "$file" && ! grep -qE "${NEEDED[$i]}" "$file"; then
      echo "FAIL imports/$(basename "$(dirname "$file")")/$(basename "$file"): uses [${SYMS[$i]}] without [${NEEDED[$i]}]"
      fails=1
    fi
  done < <(find "$SRC/virtuoso.bar" "$SRC/virtuoso.menu" "$SRC/virtuoso.theme-name" "$SRC/virtuoso.workspaces" "$SRC/virtuoso.wave" -name "*.qml" -print0 2>/dev/null | grep -zE "/(${FILES[$i]})\$" || true)
done

((fails == 0)) && echo "PASS qml-imports (all symbols covered)"
exit $fails
