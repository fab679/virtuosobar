# Places the Wave widget in centerEnd right after the lyrics widget (song
# text and song controls belong together), else appends to centerEnd.
# Skips when already placed anywhere.
def menuId: (if type == "object" then .id else . end);
def hasWave: ([.bar.layout[][]? | select(menuId == "virtuoso.wave")] | length > 0);
if hasWave then . else
.bar.layout.centerEnd |= (
  if type != "array" then [{"id": "virtuoso.wave"}]
  else (. as $arr
    | ([range(0; length) | select($arr[.] | menuId == "crmne.lyrics")] | first // null) as $i
    | if $i == null then . + [{"id": "virtuoso.wave"}]
      else .[0:$i + 1] + [{"id": "virtuoso.wave"}] + .[$i + 1:]
      end)
  end)
end
