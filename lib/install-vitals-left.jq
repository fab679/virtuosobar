# Moves the Vitals widget to the end of the left section (after the theme
# name), keeping its entry — and any settings on it — intact. Skips when it
# is already left or not on the bar at all.
def menuId: (if type == "object" then .id else . end);
([.bar.layout.left[]? | select(menuId == "lxp.vitals")] | length > 0) as $inLeft
| ([.bar.layout[][]? | select(menuId == "lxp.vitals")] | first // null) as $entry
| if $inLeft or $entry == null then .
  else (.bar.layout |= with_entries(.value |= (if type == "array"
    then map(select(menuId != "lxp.vitals")) else . end)))
    | .bar.layout.left = ((.bar.layout.left // []) + [$entry])
  end
