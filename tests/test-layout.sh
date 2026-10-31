#!/bin/bash
# Focused regression suite for VirtuosoBar's shell.json layout edits.
# Run: ./tests/test-layout.sh   (needs jq; touches nothing outside this repo)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESTORE_FILTER="${FILTER:-$SRC/lib/uninstall-restore.jq}"
PLACE_FILTER="$SRC/lib/install-placement.jq"
SWAP_FILTER="$SRC/lib/install-menu-swap.jq"
fails=0

check() { # name, filter, input-json, expected-json
  local name="$1" filter="$2" input="$3" expected="$4" actual want
  actual=$(jq -S -f "$filter" "$input")
  want=$(jq -S . "$expected")
  if [[ $actual == "$want" ]]; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    diff <(echo "$want") <(echo "$actual") || true
    fails=1
  fi
}

echo "== uninstall restore: menu icon must always come back =="
for input in "$SRC"/tests/fixtures/restore-in-*.json; do
  case_name=$(basename "$input" .json)
  case_name=${case_name#restore-in-}
  check "restore/$case_name" "$RESTORE_FILTER" "$input" "$SRC/tests/fixtures/restore-expected-$case_name.json"
done

echo "== uninstall restore: post-condition sweep =="
for input in "$SRC"/tests/fixtures/restore-in-*.json; do
  case_name=$(basename "$input" .json)
  case_name=${case_name#restore-in-}
  menus=$(jq -f "$RESTORE_FILTER" "$input" | jq '[.bar.layout[][]? | select((if type == "object" then .id else . end) == "omarchy.menu")] | length')
  virtuoso=$(jq -f "$RESTORE_FILTER" "$input" | jq '[.bar.layout[][]? | select(((if type == "object" then .id else . end) | tostring) | startswith("virtuoso."))] | length')
  if [[ $menus == 1 && $virtuoso == 0 ]]; then
    echo "PASS invariant/$case_name (one menu, no virtuoso.* entries)"
  else
    echo "FAIL invariant/$case_name (menus=$menus virtuoso=$virtuoso)"
    fails=1
  fi
done

echo "== install placement: theme name lands after hyprmoncfg, once =="
place_in=$(mktemp)
trap 'rm -f "$place_in"' EXIT
jq -n '{"version":1,"bar":{"layout":{"left":[{"id":"virtuoso.menu"},{"id":"omarchy.workspaces"},{"id":"crmne.hyprmoncfg"}]}}}' >"$place_in"
once=$(jq -S -f "$PLACE_FILTER" "$place_in" | jq -c '[.bar.layout.left[] | .id]')
twice=$(jq -S -f "$PLACE_FILTER" "$place_in" | jq -f "$PLACE_FILTER" | jq -c '[.bar.layout.left[] | .id]')
if [[ $once == '["virtuoso.menu","omarchy.workspaces","crmne.hyprmoncfg","virtuoso.theme-name"]' && $twice == "$once" ]]; then
  echo "PASS place/insert-after-hyprmoncfg (idempotent)"
else
  echo "FAIL place (once=$once twice=$twice)"
  fails=1
fi

echo "== install cleanup: retired hearth button dropped =="
cleanup_in=$(mktemp)
trap 'rm -f "$place_in" "${swap_in:-}" "$cleanup_in"' EXIT
jq -n '{"version":1,"bar":{"layout":{"right":[{"id":"omarchy.tray"},{"id":"virtuoso.hearth"}]}}}' >"$cleanup_in"
cleaned=$(jq -S -f "$SRC/lib/install-cleanup.jq" "$cleanup_in" | jq -c '[.bar.layout.right[] | .id]')
if [[ $cleaned == '["omarchy.tray"]' ]]; then
  echo "PASS cleanup/drop-hearth"
else
  echo "FAIL cleanup (got=$cleaned)"
  fails=1
fi

echo "== install menu swap: roundtrip =="
swap_in=$(mktemp)
jq -n '{"version":1,"bar":{"layout":{"left":[{"id":"omarchy.menu"},{"id":"omarchy.workspaces"}]}}}' >"$swap_in"
swapped=$(jq -S -f "$SWAP_FILTER" "$swap_in" | jq -c '[.bar.layout.left[] | .id]')
if [[ $swapped == '["virtuoso.menu","omarchy.workspaces"]' ]]; then
  echo "PASS swap/to-wordmark"
else
  echo "FAIL swap (got=$swapped)"
  fails=1
fi

echo "== install workspace swap: roundtrip =="
wsswapped=$(jq -S -f "$SRC/lib/install-workspace-swap.jq" "$swap_in" | jq -c '[.bar.layout.left[] | .id]')
if [[ $wsswapped == '["omarchy.menu","virtuoso.workspaces"]' ]]; then
  echo "PASS swap/to-glow-workspaces"
else
  echo "FAIL swap-workspaces (got=$wsswapped)"
  fails=1
fi

echo "== install wave place: after lyrics, once =="
wave_in=$(mktemp)
jq -n '{"version":1,"bar":{"layout":{"centerEnd":[{"id":"omarchy.weather"},{"id":"crmne.lyrics"},{"id":"omarchy.spacer"}]}}}' >"$wave_in"
waved=$(jq -S -f "$SRC/lib/install-wave-place.jq" "$wave_in" | jq -c '[.bar.layout.centerEnd[] | .id]')
waved_again=$(jq -S -f "$SRC/lib/install-wave-place.jq" "$wave_in" | jq -f "$SRC/lib/install-wave-place.jq" | jq -c '[.bar.layout.centerEnd[] | .id]')
if [[ $waved == '["omarchy.weather","crmne.lyrics","virtuoso.wave","omarchy.spacer"]' && $waved_again == "$waved" ]]; then
  echo "PASS wave/after-lyrics (idempotent)"
else
  echo "FAIL wave (once=$waved twice=$waved_again)"
  fails=1
fi

echo "== install vitals move: settings kept, left, once =="
vitals_in=$(mktemp)
wordmark_in=$(mktemp)
trap 'rm -f "$place_in" "$swap_in" "$cleanup_in" "$vitals_in" "$wave_in" "$wordmark_in"' EXIT
jq -n '{"version":1,"bar":{"layout":{"left":[{"id":"virtuoso.menu"}],"right":[{"id":"omarchy.tray"},{"cpuCoreViewMode":"spark","id":"lxp.vitals","pollIntervalMs":500}]}}}' >"$vitals_in"
moved=$(jq -S -f "$SRC/lib/install-vitals-left.jq" "$vitals_in")
moved_left=$(echo "$moved" | jq -c '.bar.layout.left')
moved_right=$(echo "$moved" | jq -c '[.bar.layout.right[] | .id]')
moved_again=$(echo "$moved" | jq -f "$SRC/lib/install-vitals-left.jq" | jq -c '.bar.layout.left')
if [[ $moved_left == '[{"id":"virtuoso.menu"},{"cpuCoreViewMode":"spark","id":"lxp.vitals","pollIntervalMs":500}]' && $moved_right == '["omarchy.tray"]' && $moved_again == "$moved_left" ]]; then
  echo "PASS vitals/to-left (settings kept, idempotent)"
else
  echo "FAIL vitals (left=$moved_left right=$moved_right)"
  fails=1
fi

echo "== wordmark: set is idempotent, reset removes key =="
jq -n '{"version":1,"bar":{"layout":{"left":[{"id":"virtuoso.menu"},{"id":"omarchy.clock"}]}}}' >"$wordmark_in"
wm_set=$(jq --arg wm 'omarchy <img src=x>' -f "$SRC/lib/wordmark-set.jq" "$wordmark_in" | jq -c '.bar.layout.left')
wm_set_again=$(jq --arg wm 'omarchy <img src=x>' -f "$SRC/lib/wordmark-set.jq" "$wordmark_in" | jq --arg wm 'omarchy <img src=x>' -f "$SRC/lib/wordmark-set.jq" | jq -c '.bar.layout.left')
wm_reset=$(jq --arg wm 'omarchy' -f "$SRC/lib/wordmark-set.jq" "$wordmark_in" | jq --arg wm "" -f "$SRC/lib/wordmark-set.jq" | jq -c '.bar.layout.left')
if [[ $wm_set == '[{"id":"virtuoso.menu","wordmark":"omarchy <img src=x>"},{"id":"omarchy.clock"}]' && $wm_set_again == "$wm_set" && $wm_reset == '[{"id":"virtuoso.menu"},{"id":"omarchy.clock"}]' ]]; then
  echo "PASS wordmark/set-reset (idempotent, markup stored raw for PlainText sink)"
else
  echo "FAIL wordmark (set=$wm_set reset=$wm_reset)"
  fails=1
fi

exit $fails
