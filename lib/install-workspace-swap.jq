.bar.layout |= with_entries(.value |= (if type == "array" then map(
  if type == "object" then (if .id == "omarchy.workspaces" then .id = "virtuoso.workspaces" else . end)
  elif . == "omarchy.workspaces" then "virtuoso.workspaces"
  else . end) else . end))
