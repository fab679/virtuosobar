#!/bin/bash
# Switch the VirtuosoBar shape or toggle widget dividers.
# Prints the current value when given none. Applies instantly (hot-reload).
set -euo pipefail

SHELL_JSON="$HOME/.config/omarchy/shell.json"

fail() { echo "style: $*" >&2; exit 1; }
[[ -f $SHELL_JSON ]] || fail "no shell.json at $SHELL_JSON"
command -v jq >/dev/null || fail "jq not found"

if (($# == 0)); then
  jq -r '.bar.virtuoso.style // "notch"' "$SHELL_JSON"
  exit 0
fi

toggle_key() {
  case "$1" in
    dividers) echo "dividers" ;;
    capsules) echo "capsules" ;;
    shimmer) echo "shimmer" ;;
    audioglow) echo "audioGlow" ;;
    *) echo "" ;;
  esac
}

if [[ -n $(toggle_key "$1") ]]; then
  key=$(toggle_key "$1")
  if (($# == 1)); then
    jq -r --arg key "$key" 'if .bar.virtuoso[$key] == false then "off" else "on" end' "$SHELL_JSON"
    exit 0
  fi
  [[ ${2:-} =~ ^(on|off)$ ]] || fail "usage: style.sh $1 [on|off]"
  tmp=$(mktemp)
  if [[ $2 == on ]]; then
    jq --arg key "$key" '.bar.virtuoso[$key] = true' "$SHELL_JSON" >"$tmp"
  else
    jq --arg key "$key" '.bar.virtuoso[$key] = false' "$SHELL_JSON" >"$tmp"
  fi
  mv "$tmp" "$SHELL_JSON"
  echo "VirtuosoBar $1: $2"
  exit 0
fi

if [[ $1 == "cycle" ]]; then
  case $(jq -r '.bar.virtuoso.style // "notch"' "$SHELL_JSON") in
    notch) style="fit" ;;
    fit) style="dock" ;;
    dock) style="full" ;;
    *) style="notch" ;;
  esac
else
  style="$1"
  [[ $style =~ ^(notch|fit|dock|full)$ ]] || fail "usage: style.sh [notch|fit|dock|full|cycle] | dividers|capsules|shimmer|audioglow [on|off]"
fi

tmp=$(mktemp)
jq --arg style "$style" '.bar.virtuoso.style = $style' "$SHELL_JSON" >"$tmp"
mv "$tmp" "$SHELL_JSON"
echo "VirtuosoBar style: $style"
