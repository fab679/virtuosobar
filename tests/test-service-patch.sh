#!/bin/bash
# Logic test for lib/patch-service-widget.py: anchors patch, reruns skip,
# unknown plugins are left alone. Uses synthetic fixtures in a temp dir.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/crmne.todoist" "$work/whatever.fake"

cat >"$work/crmne.todoist/BarWidget.qml" <<'EOF'
Panel {
    moduleName: "crmne.todoist"
    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    Component.onCompleted: if (service) service.registerWidget(root)
}
EOF
echo 'Item {}' >"$work/whatever.fake/BarWidget.qml"

out=$(python3 "$SRC/lib/patch-service-widget.py" "$work/crmne.todoist/BarWidget.qml" "$work/whatever.fake/BarWidget.qml")
echo "$out"
if echo "$out" | grep -q "PATCHED $work/crmne.todoist" \
  && echo "$out" | grep -q "SKIP $work/whatever.fake.*unknown plugin" \
  && grep -q "VirtuosoBar service fallback" "$work/crmne.todoist/BarWidget.qml" \
  && grep -q "Component.onCompleted: resolveService()" "$work/crmne.todoist/BarWidget.qml" \
  && [[ -f $work/crmne.todoist/BarWidget.qml.bak.virtuoso ]]; then
  echo "PASS service-patch/apply (marker, handler, backup)"
else
  echo "FAIL service-patch/apply"
  fails=1
fi

rerun=$(python3 "$SRC/lib/patch-service-widget.py" "$work/crmne.todoist/BarWidget.qml")
if [[ $rerun == "SKIP $work/crmne.todoist/BarWidget.qml: already patched" ]]; then
  echo "PASS service-patch/idempotent"
else
  echo "FAIL service-patch/idempotent (got: $rerun)"
  fails=1
fi

exit $fails
