#!/usr/bin/env python3
"""Generate a fixed user shadow of Omarchy's monitor-workspaces.lua.

Upstream bug: M.move_to_monitor's final focus uses moved.id, a snapshot taken
before adopt() renumbers the workspace into its new block — so after moving a
workspace across monitors, focus jumps back to the stale (now empty) id,
usually on the monitor it just left. The fix makes adopt() return the new id
(or nil when the block is full) and focuses that instead.

/usr/share is package-owned, so the fix ships as a user shadow module. The
Hyprland bootstrap puts ~/.config ahead of $OMARCHY_PATH on package.path, so
~/.config/default/hypr/monitor-workspaces.lua wins over stock. The shadow is
regenerated from current stock on every run: re-run after `omarchy update`,
and delete the file to return to pure stock.

Each anchor must match exactly once; anything else fails loudly instead of
writing a half-patched file (e.g. when an Omarchy update reshapes the code).

Usage: patch-workspace-move.py <stock-file> <shadow-file>
"""
import datetime
import subprocess
import sys

MARKER = "VirtuosoBar move fix"

A1_OLD = "-- taking the first free one otherwise. False when all ten are taken."
A1_NEW = """-- taking the first free one otherwise. Returns the new id, or nil when all
-- ten are taken. (MARKER: callers need the post-adopt id.)""".replace("MARKER", MARKER)

A2_OLD = """  for _, id in ipairs(candidates) do
    if not hl.get_workspace(id) then
      renumber(workspace, id)
      return true
    end
  end

  return false
end"""
A2_NEW = """  for _, id in ipairs(candidates) do
    if not hl.get_workspace(id) then
      renumber(workspace, id)
      return id
    end
  end

  return nil
end"""

A3_OLD = """    local block = by_connector[moved.monitor.name]
    if block and block_of_id(id) ~= block then
      adopt(moved, block)
    end"""
A3_NEW = """    local block = by_connector[moved.monitor.name]
    local final_id = id
    if block and block_of_id(id) ~= block then
      final_id = adopt(moved, block) or id
    end"""

A4_OLD = """    -- Settling the monitor it left can take focus; it belongs with the
    -- workspace that moved.
    hl.dispatch(hl.dsp.focus({ workspace = tostring(moved.id) }))"""
A4_NEW = """    -- Settling the monitor it left can take focus; it belongs with the
    -- workspace that moved. Focus the post-adopt id: moved.id is the stale
    -- pre-move snapshot once adopt() renumbers. (MARKER)""".replace("MARKER", MARKER) + """
    hl.dispatch(hl.dsp.focus({ workspace = tostring(final_id) }))"""

PATCHES = [(A1_OLD, A1_NEW), (A2_OLD, A2_NEW), (A3_OLD, A3_NEW), (A4_OLD, A4_NEW)]


def omarchy_version():
    try:
        out = subprocess.run(["pacman", "-Q", "omarchy"], capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            return out.stdout.strip()
    except OSError:
        pass
    try:
        out = subprocess.run(["pacman", "-Q", "omarchy-dev"], capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            return out.stdout.strip()
    except OSError:
        pass
    return "omarchy (version unknown)"


def main(argv):
    if len(argv) != 3:
        print(f"Usage: {argv[0]} <stock-file> <shadow-file>", file=sys.stderr)
        return 1
    stock_path, shadow_path = argv[1], argv[2]
    try:
        with open(stock_path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        print(f"FAIL: cannot read stock file: {e}", file=sys.stderr)
        return 1
    for old, _ in PATCHES:
        n = text.count(old)
        if n != 1:
            print(f"FAIL: anchor found {n}x (expected 1x): {old[:70]}...", file=sys.stderr)
            print("The stock file changed shape (Omarchy update?). Not writing.", file=sys.stderr)
            return 1
    for old, new in PATCHES:
        text = text.replace(old, new, 1)
    header = (
        "-- VirtuosoBar shadow of default.hypr.monitor-workspaces. This file wins\n"
        "-- over $OMARCHY_PATH because the Hyprland bootstrap puts ~/.config first\n"
        "-- on package.path. Generated %s from stock (%s); carries the\n"
        "-- post-adopt focus fix, marked (%s). Re-run fix-workspace-move.sh\n"
        "-- after `omarchy update`; delete this file to return to pure stock.\n\n"
    ) % (datetime.date.today().isoformat(), omarchy_version(), MARKER)
    try:
        with open(shadow_path, "w", encoding="utf-8") as f:
            f.write(header + text)
    except OSError as e:
        print(f"FAIL: cannot write shadow file: {e}", file=sys.stderr)
        return 1
    print(f"WROTE {shadow_path} ({MARKER})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
