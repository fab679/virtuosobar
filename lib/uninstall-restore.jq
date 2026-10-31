def menuId: (if type == "object" then .id else . end);

# Swap one virtuoso widget back to stock, or drop it if stock is already
# there (no duplicates, positions preserved).
def restore($virt; $stock; $hasStock):
  if menuId == $virt
  then (if $hasStock then empty
        else (if type == "object" then .id = $stock else $stock end)
        end)
  else . end;

([.bar.layout[][]? | select(menuId == "omarchy.menu")] | length > 0) as $hasO
| ([.bar.layout[][]? | select(menuId == "omarchy.workspaces")] | length > 0) as $hasW
| ([.bar.layout[][]? | select(menuId == "omarchy.clock")] | length > 0) as $hasC

# Swap the wordmark, workspaces and clock back, and drop everything whose
# plugin is gone after uninstall (theme name, wave, and the sci-fi set).
| .bar.layout |= with_entries(.value |= (if type == "array"
  then map(restore("virtuoso.menu"; "omarchy.menu"; $hasO)
         | restore("virtuoso.workspaces"; "omarchy.workspaces"; $hasW)
         | restore("virtuoso.clock"; "omarchy.clock"; $hasC)
         | select(menuId != "virtuoso.theme-name" and menuId != "virtuoso.hearth" and menuId != "virtuoso.wave"
             and menuId != "virtuoso.stream" and menuId != "virtuoso.reactor"
             and menuId != "virtuoso.gauges" and menuId != "virtuoso.settings"))
  else . end))

# Guarantee the post-condition: exactly one menu trigger. If neither form
# survived (manual edits, older uninstaller, clobbered config), re-add stock
# at the front of the left section instead of leaving the bar menu-less.
| if ([.bar.layout[][]? | select(menuId == "omarchy.menu")] | length > 0) then .
  else .bar.layout.left = ([{"id": "omarchy.menu"}]
    + ((.bar.layout.left // []) | if type == "array" then . else [] end))
  end
