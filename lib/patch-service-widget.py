#!/usr/bin/env python3
"""Patch service-backed third-party widgets to work under VirtuosoBar.

A replacement bar hands widgets a service-less shell facade (Omarchy
security design), so bar.shell.serviceFor() is null there and widgets like
Todoist lose their service: panel never opens, clicks do nothing. The patch
turns the lookup into resolveService(), which falls back to a locally
created Service driving the panel only. On the stock bar the lookup wins
and no fallback is ever made.

Idempotent: files already carrying the marker are skipped. Each patched
file keeps exactly one backup (<name>.bak.virtuoso); re-runs reuse it.

Usage: patch-service-widget.py <BarWidget.qml> [<BarWidget.qml> ...]
Patches are matched by plugin directory name (crmne.todoist, crmne.lyrics,
denis.yoink). Unknown plugins are left untouched with a warning.
"""
import os
import sys

MARKER = "VirtuosoBar service fallback"

COMMENT = """\
{ind}// {mark}: replacement bars hand widgets a
{ind}// service-less shell facade (Omarchy design), so serviceFor() is null
{ind}// there. Fall back to a local Service driving the panel only.
{ind}// Stock bar is unaffected: the lookup wins and no fallback is made."""

TODOIST_FIND = "    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null"
TODOIST_ONCOMPLETED = "    Component.onCompleted: if (service) service.registerWidget(root)"

LYRICS_FIND = '  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("crmne.lyrics") : null'
YOINK_FIND = '  readonly property var downloadService: bar && bar.shell ? bar.shell.serviceFor("denis.yoink") : null'


def block(ind, prop, lookup, extra_props="", on_completed=""):
    lines = [COMMENT.format(ind=ind, mark=MARKER)]
    lines.append(f"{ind}property var {prop}: null")
    lines.append(f"{ind}property var fallbackService: null")
    lines.append(f"{ind}Component {{ id: fallbackServiceComponent; Service {{{extra_props}}} }}")
    lines.append(f"{ind}function resolveService() {{")
    lines.append(f"{ind}{ind}var found = {lookup}")
    lines.append(f"{ind}{ind}if (found) {{ {prop} = found; return }}")
    lines.append(f"{ind}{ind}if (!fallbackService) fallbackService = fallbackServiceComponent.createObject(root)")
    lines.append(f"{ind}{ind}{prop} = fallbackService")
    lines.append(f"{ind}}}")
    lines.append(f"{ind}onBarChanged: resolveService()")
    if on_completed:
        lines.append(f"{ind}{on_completed}")
    return "\n".join(lines)


PATCHES = {
    "crmne.todoist": [
        (TODOIST_FIND, block("    ", "service",
                             "bar && bar.shell ? bar.shell.serviceFor(moduleName) : null",
                             extra_props=" enableShortcuts: false; enableNotifications: false")),
        (TODOIST_ONCOMPLETED, "    Component.onCompleted: resolveService()"),
    ],
    "crmne.lyrics": [
        (LYRICS_FIND, block("  ", "service",
                            'bar && bar.shell ? bar.shell.serviceFor("crmne.lyrics") : null',
                            on_completed="Component.onCompleted: resolveService()")),
    ],
    "denis.yoink": [
        (YOINK_FIND, block("  ", "downloadService",
                           'bar && bar.shell ? bar.shell.serviceFor("denis.yoink") : null',
                           on_completed="Component.onCompleted: resolveService()")),
    ],
}


def patch_file(path):
    plugin = os.path.basename(os.path.dirname(os.path.abspath(path)))
    if plugin not in PATCHES:
        return f"SKIP {path}: unknown plugin '{plugin}'"
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if MARKER in text:
        return f"SKIP {path}: already patched"
    for old, _ in PATCHES[plugin]:
        if text.count(old) != 1:
            return f"FAIL {path}: anchor found {text.count(old)}x (expected 1x): {old[:60]}..."
    for old, new in PATCHES[plugin]:
        text = text.replace(old, new, 1)
    backup = path + ".bak.virtuoso"
    if not os.path.exists(backup):
        with open(backup, "w", encoding="utf-8") as f:
            with open(path, encoding="utf-8") as orig:
                f.write(orig.read())
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return f"PATCHED {path} (backup: {backup})"


def main(argv):
    failed = False
    for path in argv[1:]:
        if not os.path.isfile(path):
            print(f"FAIL {path}: not a file")
            failed = True
            continue
        result = patch_file(path)
        print(result)
        if result.startswith("FAIL"):
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
