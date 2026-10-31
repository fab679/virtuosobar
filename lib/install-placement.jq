def hasTN: [.bar.layout[][]? | select(type == "object" and .id == "virtuoso.theme-name")] | length > 0;
if hasTN then . else
.bar.layout.left |= (
  if type != "array" then [{"id": "virtuoso.theme-name"}]
  else (. as $arr
    | ([range(0; length) | select($arr[.] | type == "object" and .id == "crmne.hyprmoncfg")] | first // null) as $i
    | if $i == null then . + [{"id": "virtuoso.theme-name"}]
      else .[0:$i + 1] + [{"id": "virtuoso.theme-name"}] + .[$i + 1:]
      end)
  end)
end
