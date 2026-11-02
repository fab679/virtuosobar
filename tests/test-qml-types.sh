#!/bin/bash
# Element-type existence check for VirtuosoBar QML: every type a file
# instantiates must actually exist on the installed shell/Quickshell, or the
# whole file fails to load ("X is not a type") and the bar silently vanishes.
# This class of failure was hit on 2026-11-02: an Omarchy update removed the
# `ScreenMoveRemap` type and virtuoso.bar stopped loading everywhere.
#
# A type is considered existing when it is:
#   - a Qt intrinsic (whitelisted below),
#   - the basename of any .qml file under /usr/share/omarchy/shell,
#   - an inline `component Name` declared in a shell .qml,
#   - exported by a Quickshell module (its .qmltypes files),
#   - or a .qml file in the same directory as the using file.
# Run: ./tests/test-qml-types.sh   (needs only grep/find; touches nothing)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR=/usr/share/omarchy/shell
fails=0

intrinsics="Binding Canvas Column ColumnLayout Component Connections
DelegateChoice Flickable FrameAnimation GridLayout GradientStop HoverHandler
Image Instantiator Item Loader MouseArea MultiEffect NumberAnimation
PauseAnimation PathAngleArc PathArc PathCubic PathLine PathMove PathSvg
PathQuad QtObject Rectangle Repeater Row RowLayout ScriptAction
SequentialAnimation Shape ShapePath Text TextField TextInput Timer
WheelHandler Button TabButton SwipeView Flickable VerticalHeaderView
HorizontalHeaderView Gradient PropertyAnimation Behavior BehaviorOnProperty
TapHandler HoverHandler DragHandler PinchHandler PopupWindow Region Variants
FileView Process PanelWindow Panel PanelChanged Anchors ExclusiveZone PwNodePeakMonitor PwObjectWatcher"
intrinsics="$(tr -s ' \n' '  ' <<<"$intrinsics")"

# Universe: shell file basenames + inline components + Quickshell exports.
universe="$(
  {
    find "$SHELL_DIR" -name '*.qml' -printf '%f\n' | sed 's/\.qml$//' || true
    find "$SRC" -name '*.qml' -printf '%f\n' | sed 's/\.qml$//' || true
    find /usr/lib/qt6/qml -name '*.qml' -printf '%f\n' 2>/dev/null | sed 's/\.qml$//' || true
    { grep -rhoE 'component[[:space:]]+[A-Z][A-Za-z0-9_]*' "$SHELL_DIR" --include='*.qml' 2>/dev/null | awk '{print $2}'; } || true
    { grep -rhoE 'name:[[:space:]]*"[A-Z][A-Za-z0-9_]*"' /usr/lib/qt6/qml/Quickshell 2>/dev/null | sed 's/.*[[:space:]]\+"//;s/"//'; } || true
    { find /usr/lib/qt6/qml -name 'qmldir' -exec grep -hoE '^[A-Z][A-Za-z0-9_]*' {} \; 2>/dev/null; } || true
    { find /usr/lib/qt6/qml -name 'qmldir' -exec grep -hoE '^\s+([A-Z][A-Za-z0-9_]*)[[:space:]]+[0-9]' {} \; 2>/dev/null | awk '{print $1}'; } || true
  } | sort -u
)"

for file in $(find "$SRC"/virtuoso.* -name '*.qml' | sort); do
  dir=$(dirname "$file")
  # A file's own inline components (component Gauge: Item) count as types.
  own="$universe
$(grep -hoE 'component[[:space:]]+[A-Z][A-Za-z0-9_]*' "$file" 2>/dev/null | awk '{print $2}' || true)"
  while IFS= read -r tag; do
    [[ -n $tag ]] || continue
    if [[ " $intrinsics " == *" $tag "* ]]; then continue; fi
    if grep -qxF "$tag" <<<"$own"; then continue; fi
    echo "FAIL $file instantiates '$tag' — no such type in shell, Quickshell, or sibling files"
    fails=$((fails + 1))
  done < <(grep -hoE '^[[:space:]]*[A-Z][A-Za-z0-9_]*[[:space:]]*\{' "$file" | grep -oE '[A-Z][A-Za-z0-9_]*' | sort -u)
done

if (( fails > 0 )); then
  echo "qml-types: $fails missing type(s)"
  exit 1
fi
echo "PASS qml-types (every instantiated type exists)"
