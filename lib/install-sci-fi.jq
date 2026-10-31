# Wire the VirtuosoBar widgets into the layout. Idempotent: every step checks
# for the widget before touching anything, so re-running the installer never
# duplicates entries, and a layout already wired keeps its order.
#
# Only two placements are automatic: the segment clock swap and the settings
# gear. The other widgets (wave transport aside, which install-wave-place.jq
# handles) — stream, reactor, gauges — install as plugins but stay out of the
# layout until you drag them in from the bar or add them in shell.json.

def idOf: (if type == "object" then .id else . end);
def present($id): ([.bar.layout[][]? | select(idOf == $id)] | length) > 0;

# Replace the stock clock with the seven-segment one, in place. The stock
# entry's format keys are dropped: the drawn clock takes its own options.
(if present("virtuoso.clock") then .
 elif present("omarchy.clock") then
   .bar.layout |= with_entries(.value |= (if type == "array" then map(
     if type == "object" and .id == "omarchy.clock"
     then {"id": "virtuoso.clock", "use24h": true, "showSecondsRing": true,
           "blinkColons": true, "ghostSegments": true}
     else . end) else . end))
 else . end)

# The settings gear closes the right section.
| (if present("virtuoso.settings") then .
   else .bar.layout.right |= ((if type == "array" then . else [] end) + [{"id": "virtuoso.settings"}])
   end)