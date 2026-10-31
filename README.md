# VirtuosoBar

A sci-fi **V2 notch bar** for Omarchy, built over the stock bar engine:
same widgets, panels, hover drawers, and drag-and-drop — V2 silhouette,
starship interior.

## The bar

- Full-bleed strip with **swept bezier wing shoulders** and **HUD targeting
  brackets** floating in the wing cutouts
- **Neon hairline** along wings and bottom edge: breathes with the theme
  accent when silent, burns with the audio mix when loud
- **Power-on boot sweep** when the shell starts, and a brief **theme
  glitch** whenever the palette changes (each toggleable)
- **HUD capsules** behind every widget, hairline dividers, region seams
- Slow **shimmer sweep** behind the widgets (stilled by reduced motion)
- **VIRTUOSO wordmark** opening the stock Omarchy menu (right click: terminal)
- **Theme name with Hearth deck** — live theme name closing the left
  section; click deals a fanned 16:9 card browser for themes and wallpapers
- **Vitals** in the left cluster (CPU spark at a glance)

## The sci-fi widgets

| Widget | What it does |
|---|---|
| `virtuoso.workspaces` | Per-monitor workspaces with seven pill styles — digits, numbers, halo, kanji (一..十), rings, aurora stretch-bars, and a pacman that runs to and eats the focused slot. Ion trail on every switch; layout marks (tile / ring / triangle) on the active pill. |
| `virtuoso.clock` | Seven-segment clock with ghost segments, blinking colon and a seconds tick-ring. Left click: the calendar (month grid, week numbers, month stepping, weekday · time hero). Right click: 24h ↔ 12h. Day names follow the Omarchy language. |
| `virtuoso.settings` | The ⚙ gear: configure the bar without a terminal — name (wordmark), surface style, background, position, workspace pill style. |
| `virtuoso.wave` | Live audio spectrum (cava) with player transport. |
| `virtuoso.stream` | Network throughput as a data-stream waveform. *(installed, not auto-wired)* |
| `virtuoso.reactor` | Battery as a reactor core. *(installed, not auto-wired)* |
| `virtuoso.gauges` | HUD ring gauges: CPU · RAM · TEMP. *(installed, not auto-wired)* |

Everything follows the system theme (`bar.background`, `bar.text` at low
alpha): change the Omarchy theme and VirtuosoBar changes with it. No
hardcoded colors anywhere. All motion respects reduced-motion.

## Install on a new PC

On any Omarchy machine (Omarchy Quattro or newer), logged into GitHub:

```bash
git clone https://github.com/fab679/virtuosobar.git
cd virtuosobar
./install.sh
```

That's it. The installer:

1. installs `cava` if it is missing (`omarchy pkg add`, idempotent)
2. validates and copies all plugins into `~/.config/omarchy/plugins/`
3. backs up your `shell.json` (timestamped, never overwritten)
4. swaps the stock menu button for the wordmark and wires the segment
   clock and the ⚙ settings gear into your layout — idempotent, so
   re-running never duplicates anything
5. activates VirtuosoBar

The other widgets on your bar (todoist, lyrics, weather, hyprmoncfg, …)
are separate plugins — reinstall them with `omarchy plugin add <git-url>`
if the new machine does not have them. The installer leaves any unknown
widget entries alone, so your layout survives.

## Configure without a terminal

Click the ⚙ on the right end of the bar:

- **Name** — the letterspaced wordmark on the far left
- **Surface** — notch / fit / dock / full, background, position
- **Workspaces** — pill style, applies instantly

Effect keys (dividers, capsules, shimmer, audio glow, breathing glow, boot
sweep, theme glitch) are scriptable:

```bash
./style.sh fit                  # surface style: notch | fit | dock | full
./style.sh dividers off         # any of: dividers capsules shimmer audioGlow breathing boot glitch
./wordmark.sh set VOYAGER       # custom wordmark
```

## Uninstall

```bash
./uninstall.sh
```

Restores the stock bar, menu button and clock, removes every Virtuoso
plugin. Your `shell.json` backups are never touched.

## Tests

```bash
bash tests/test-layout.sh       # jq wiring is idempotent and correct
bash tests/test-qml-imports.sh  # every referenced shell symbol exists
```