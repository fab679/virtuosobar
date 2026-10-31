#!/usr/bin/env bash
# Set the virtuosobar wordmark text shown at the far left of the bar.
# The bar renders it uppercased in the letterspaced house style.
# shell.json hot-reloads, so the change applies instantly, no restart.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

usage() {
  cat <<'EOF'
Usage:
  ./wordmark.sh set <text>   Show <text> as the bar wordmark (stored as typed)
  ./wordmark.sh show         Print the current wordmark (default: VIRTUOSO)
  ./wordmark.sh reset        Go back to VIRTUOSO
EOF
}

cmd="${1:-}"
case "$cmd" in
  set)
    text="${2:-}"
    if [[ -z $text ]]; then echo "error: ./wordmark.sh set needs text" >&2; exit 1; fi
    if ((${#text} > 64)); then echo "error: keep it under 64 characters" >&2; exit 1; fi
    tmp="$(mktemp)"
    jq --arg wm "$text" -f "$SRC/lib/wordmark-set.jq" "$SHELL_JSON" >"$tmp"
    mv "$tmp" "$SHELL_JSON"
    echo "wordmark: ${text^^}"
    ;;
  show)
    jq -r '[.bar.layout[][] | select((.id // "") == "virtuoso.menu") | .wordmark // empty] | first // "VIRTUOSO"' "$SHELL_JSON"
    ;;
  reset)
    tmp="$(mktemp)"
    jq --arg wm "" -f "$SRC/lib/wordmark-set.jq" "$SHELL_JSON" >"$tmp"
    mv "$tmp" "$SHELL_JSON"
    echo "wordmark: VIRTUOSO"
    ;;
  *) usage; exit 1 ;;
esac
