.bar.layout |= with_entries(.value |= (if type == "array" then map(
  if type == "object" then (if .id == "omarchy.menu" then .id = "virtuoso.menu" else . end)
  elif . == "omarchy.menu" then "virtuoso.menu"
  else . end) else . end))
