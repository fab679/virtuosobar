# Drops layout entries for the retired standalone Hearth button. The deck
# now lives in the theme name widget; a stale entry would dangle.
.bar.layout |= with_entries(.value |= (if type == "array"
  then map(select((if type == "object" then .id else . end) != "virtuoso.hearth"))
  else . end))
