# VirtuosoBar

A sci-fi notch bar for **Omarchy**, built as real Omarchy shell plugins over
the stock bar engine — same widgets, panels, hover drawers, drag-and-drop;
a starship-interior silhouette on top.

**Is it really a plugin? Yes.** The repo ships ten Omarchy shell plugins:
one full-bar plugin (`virtuoso.bar`, kind `bar`) and nine bar-widget plugins
(kind `bar-widget`). Each has an official `manifest.json`, passes
`omarchy plugin validate`, is discovered by the shell's plugin registry,
and hot-reloads from `~/.config/omarchy/plugins/`. The bar is not a fork of
Omarchy's shell — it is loaded *by* Omarchy's shell, which is why themes,
panels and the settings gear all keep working.

---

## Requirements

| Requirement | Why | Provided by |
|---|---|---|
| **Omarchy** (current) | The shell, plugin registry, fonts, `omarchy-*` CLI | omarchy.org |
| **git** | To clone this repo | preinstalled on Omarchy |
| **jq** | Installer, uninstaller, menu checkmarks | preinstalled on Omarchy (checked by the installer) |
| **cava** | Live spectrum for the Wave widget | preinstalled on Omarchy (re-installed by the installer if missing) |
| **JetBrainsMono Nerd Font** | The pacman workspace glyph | preinstalled on Omarchy |

Nothing else: no forks, no patched files, nothing under `/usr/share/omarchy`
is ever modified. Everything installs into your home directory.

## Install on a new PC

```bash
git clone https://github.com/fab679/virtuosobar.git
cd virtuosobar
./install.sh
```

The installer is idempotent — run it again any time to update. It will:

1. check `jq` (fails early if missing) and install `cava` if absent
2. validate and copy all ten plugins into `~/.config/omarchy/plugins/`
3. install the `virtuoso-style` CLI into `~/.local/bin/`
4. add the **Bar** section to your Omarchy menu — only if you do not
   already have a menu file; your existing one is never touched
5. back up your `shell.json` (timestamped copy, never overwritten)
6. rewire the layout: menu button → wordmark, stock clock → segment
   clock, and the ⚙ settings gear at the end of the right section —
   all steps check before writing, so nothing duplicates
7. activate VirtuosoBar

Your other widgets (todoist, lyrics, weather, hyprmoncfg, …) are separate
plugins and are left exactly where they are. On a brand-new machine, add
them with `omarchy plugin add <git-url>` and the bar picks them up.

Log out and back in (or `omarchy restart shell`) if anything looks stale.

## What you get

- **Surface**: full-bleed strip with swept bezier wing shoulders, HUD
  targeting brackets, neon hairline that breathes with the accent and
  burns with the audio mix, HUD capsules, hairline dividers, shimmer
  sweep, power-on boot animation, theme-change glitch. Four shapes:
  notch (default), fit, dock, full.
- **Workspaces** (`virtuoso.workspaces`): per-monitor workspaces
  (each screen starts at 1) with seven pill styles — digits, numbers,
  halo, kanji 一二三, rings, aurora stretch-bars, and a pacman that runs
  to and eats the focused slot. Ion trail on every switch, layout marks
  (tile / ring / triangle) on the active pill.
- **Clock** (`virtuoso.clock`): seven-segment display with ghost
  segments, blinking colon, seconds tick-ring and the date beside it.
  Left click opens the calendar (month grid, week numbers, month
  stepping, weekday · time hero). Right click flips 24h ↔ 12h. Day and
  month names follow the Omarchy language setting.
- **Settings gear** (`virtuoso.settings`): configure the bar without a
  terminal — name (wordmark), surface style, background, position,
  workspace pill style. Changes land instantly.
- **Wave** (`virtuoso.wave`): live audio spectrum with player transport
  (hides while idle).
- **Menu, theme name, hearth deck**: the stock menu behind the wordmark,
  the live theme name with the fanned theme-card browser.

Also installed but **not auto-wired** (add them from the bar by dragging,
or with `omarchy bar put <id>`): `virtuoso.stream` (network waveform),
`virtuoso.reactor` (battery core), `virtuoso.gauges` (CPU · RAM · TEMP).

## Configure it

Three ways, all changing the same `shell.json`:

1. **The ⚙ gear** (right end of the bar) — name, surface, background,
   position, pill style.
2. **The Omarchy menu** — Super+Space → *Bar*: background looks and
   surface styles with ✓ on the active one, plus a shortcut to the gear.
3. **The CLI**:

```bash
virtuoso-style background glassy     # opaque | glassy | none
virtuoso-style fit                   # notch | fit | dock | full
virtuoso-style pill kanji            # digits | numbers | halo | kanji | rings | aurora | pacman
virtuoso-style name VOYAGER          # the wordmark
virtuoso-style shimmer off           # dividers capsules shimmer audioGlow breathing boot glitch
```

## Uninstall

```bash
./uninstall.sh
```

Restores the stock bar, menu button and clock, removes all Virtuoso
plugins and menu rows are left as installed. Your `shell.json` backups
(`shell.json.bak.virtuoso.*`) are never touched.

## Updating

```bash
cd virtuosobar && git pull && ./install.sh
```

If you edited a widget in `~/.config/omarchy/plugins/` directly, copy it
back into this repo before pushing — the repo is the source of truth.

## Tests

```bash
bash tests/test-layout.sh        # layout wiring: idempotent, correct
bash tests/test-qml-imports.sh   # every referenced shell symbol exists
bash tests/test-qml-types.sh     # every instantiated type exists on the installed shell
```

## Troubleshooting

- **Bar did not change after editing a file** — the shell occasionally
  misses a hot-reload; `omarchy restart shell` always settles it.
- **No spectrum in the Wave** — check `pgrep cava`; reinstall with
  `omarchy pkg add cava`.
- **Workspaces wrong after a monitor change** — give it a second; the
  reconciler settles monitors into their own blocks of ten.