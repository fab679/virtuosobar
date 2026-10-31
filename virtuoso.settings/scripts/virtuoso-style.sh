#!/bin/bash
# VirtuosoBar surface keys, written to shell.json by the Virtuoso Settings
# panel. Same contract as the project's style.sh, with the newer effect keys
# added: positional style, on/off toggles, current value when given none.
# Applies instantly — the shell watches this file.
set -euo pipefail

SHELL_JSON="$HOME/.config/omarchy/shell.json"

fail() { echo "virtuoso-style: $*" >&2; exit 1; }
[[ -f $SHELL_JSON ]] || fail "no shell.json at $SHELL_JSON"
command -v jq >/dev/null || fail "jq not found"

STYLE_KEYS="notch fit dock full"
TOGGLE_KEYS="dividers capsules shimmer audioGlow breathing boot glitch"

if (($# == 0)); then
  jq -r '{style: (.bar.virtuoso.style // "notch"),
          dividers: ((.bar.virtuoso.dividers == false) | not),
          capsules: ((.bar.virtuoso.capsules == false) | not),
          shimmer: ((.bar.virtuoso.shimmer == false) | not),
          audioGlow: ((.bar.virtuoso.audioGlow == false) | not),
          breathing: ((.bar.virtuoso.breathing == false) | not),
          boot: ((.bar.virtuoso.boot == false) | not),
          glitch: ((.bar.virtuoso.glitch == false) | not)} | to_entries[] | "\(.key)=\(.value)"' "$SHELL_JSON"
  exit 0
fi

key=$1

# pill <style> — the workspace pill style on its layout entry.
if [[ $key == "pill" ]]; then
  (($# == 2)) || fail "usage: virtuoso-style.sh pill <style>"
  tmp=$(mktemp)
  jq --arg style "$2" '.bar.layout |= with_entries(.value |= (if type == "array" then map(
    if type == "object" and .id == "virtuoso.workspaces" then .pillStyle = $style else . end)
    else . end))' "$SHELL_JSON" >"$tmp"
  mv "$tmp" "$SHELL_JSON"
  echo "Workspace pills: $2"
  exit 0
fi

# name <text> — the wordmark on the virtuoso.menu entry.
if [[ $key == "name" ]]; then
  (($# == 2)) || fail "usage: virtuoso-style.sh name <text>"
  tmp=$(mktemp)
  jq --arg name "$2" '.bar.layout |= with_entries(.value |= (if type == "array" then map(
    if type == "object" and .id == "virtuoso.menu" then .wordmark = $name else . end)
    else . end))' "$SHELL_JSON" >"$tmp"
  mv "$tmp" "$SHELL_JSON"
  echo "Bar name: $2"
  exit 0
fi

# position <edge> — the bar's screen edge.
if [[ $key == "position" ]]; then
  (($# == 2)) || fail "usage: virtuoso-style.sh position <top|bottom|left|right>"
  [[ $2 =~ ^(top|bottom|left|right)$ ]] || fail "position must be top, bottom, left or right"
  tmp=$(mktemp)
  jq --arg position "$2" '.bar.position = $position' "$SHELL_JSON" >"$tmp"
  mv "$tmp" "$SHELL_JSON"
  echo "Bar position: $2"
  exit 0
fi

# background <look> — the bar's fill.
if [[ $key == "background" ]]; then
  (($# == 2)) || fail "usage: virtuoso-style.sh background <opaque|glassy|none>"
  [[ $2 =~ ^(opaque|glassy|none)$ ]] || fail "background must be opaque, glassy or none"
  tmp=$(mktemp)
  jq --arg look "$2" '.bar.background = $look' "$SHELL_JSON" >"$tmp"
  mv "$tmp" "$SHELL_JSON"
  echo "Bar background: $2"
  exit 0
fi

case "$key" in
  notch|fit|dock|full)
    tmp=$(mktemp)
    jq --arg style "$key" '.bar.virtuoso.style = $style' "$SHELL_JSON" >"$tmp"
    mv "$tmp" "$SHELL_JSON"
    echo "VirtuosoBar style: $key"
    exit 0
    ;;
esac

if [[ " $TOGGLE_KEYS " == *" $key "* ]]; then
  (($# == 2)) || fail "usage: virtuoso-style.sh $key [on|off]"
  [[ $2 =~ ^(on|off)$ ]] || fail "usage: virtuoso-style.sh $key [on|off]"
  tmp=$(mktemp)
  if [[ $2 == on ]]; then
    jq --arg key "$key" '.bar.virtuoso[$key] = true' "$SHELL_JSON" >"$tmp"
  else
    jq --arg key "$key" '.bar.virtuoso[$key] = false' "$SHELL_JSON" >"$tmp"
  fi
  mv "$tmp" "$SHELL_JSON"
  echo "VirtuosoBar $key: $2"
  exit 0
fi

fail "unknown key '$key' (styles: $STYLE_KEYS; toggles: $TOGGLE_KEYS)"