#!/bin/bash
# Tests for lib/patch-workspace-move.py: anchors apply to the real stock
# file, the patched copy parses (luac), the diff is only the intended
# hunks, and drift fails loudly instead of writing.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STOCK="${OMARCHY_PATH:-/usr/share/omarchy}/default/hypr/monitor-workspaces.lua"
fails=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ ! -f $STOCK ]]; then
  echo "SKIP workspace-move/apply (no stock file on this machine)"
  exit 0
fi

if ! python3 "$SRC/lib/patch-workspace-move.py" "$STOCK" "$work/shadow.lua" >/dev/null; then
  echo "FAIL workspace-move/apply (patcher exited nonzero on stock)"
  fails=1
else
  echo "PASS workspace-move/apply"
fi

if command -v luac >/dev/null; then
  if luac -p "$work/shadow.lua"; then
    echo "PASS workspace-move/luac (patched file parses)"
  else
    echo "FAIL workspace-move/luac"
    fails=1
  fi
else
  echo "SKIP workspace-move/luac (luac not installed)"
fi

# Only the four intended hunks may differ (plus the header comment block).
added=$(diff "$STOCK" "$work/shadow.lua" | grep '^>' | grep -v '^> --' || true)
if echo "$added" | grep -q "return id" \
  && echo "$added" | grep -q "return nil" \
  && echo "$added" | grep -q "local final_id = id" \
  && echo "$added" | grep -q "tostring(final_id)" \
  && [[ $(echo "$added" | wc -l) -le 8 ]]; then
  echo "PASS workspace-move/diff (only intended hunks)"
else
  echo "FAIL workspace-move/diff"
  echo "$added"
  fails=1
fi

# Drift: an anchor missing from stock must fail, not write.
cp "$STOCK" "$work/drifted.lua"
python3 - "$work/drifted.lua" <<'EOF'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t = t.replace("tostring(moved.id)", "tostring(moved.id, 2)")
open(p, "w", encoding="utf-8").write(t)
EOF
if python3 "$SRC/lib/patch-workspace-move.py" "$work/drifted.lua" "$work/should-not-exist.lua" 2>/dev/null \
  || [[ -f $work/should-not-exist.lua ]]; then
  echo "FAIL workspace-move/drift (wrote despite drift)"
  fails=1
else
  echo "PASS workspace-move/drift (fails loudly, writes nothing)"
fi

exit $fails
