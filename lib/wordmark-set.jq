# Set (or clear, when $wm is "") the custom wordmark on every virtuoso.menu
# entry. Usage: jq --arg wm "OMARCHY" -f lib/wordmark-set.jq shell.json
((.bar.layout // {}) | keys_unsorted) as $sections
| reduce $sections[] as $s (.;
    .bar.layout[$s] |= map(
      if ((.id // "") == "virtuoso.menu") then
        (if ($wm // "") == "" then del(.wordmark) else .wordmark = $wm end)
      else . end))
