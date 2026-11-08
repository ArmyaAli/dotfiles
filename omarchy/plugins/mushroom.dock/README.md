# Mushroom Grove Dock

A minimal, floating, auto-hiding application dock for the Omarchy shell. It is
a `panel` plugin with `keepLoaded: true`, so one dock surface is mounted per
screen for the whole session.

## Features

- **Floating glass pill**: borderless translucent panel themed from the active
  theme (`Color`/`Style`), with a soft shadow so it reads as floating.
- **Instance count badge.** Apps with more than one window show a coral badge
  with the window count on the top-right of their disc.
- **Circular app chrome** matching the bar's top-right controls, each app's own
  icon inside the disc.
- **Proximity magnification** computed against the unmagnified slot grid, so a
  growing icon can never feed back into its own scale.
- **Hidden by default.** It peeks in on demand and hides again. The layer-shell
  input region is masked to the dock plus a hair-thin bottom strip, so the
  hidden dock is click-through.
- **Mushroom launcher**: left click opens the Omarchy menu, right click opens a
  terminal.

## Showing and hiding

| Trigger | Effect |
|---|---|
| Tap `Super` | Peeks the dock for a few seconds |
| Bottom screen edge | Reveals the dock while the pointer is there |
| `omarchy-shell mushroom-dock peek` | Same as tapping Super |
| `omarchy-shell mushroom-dock toggle` | Pins the dock open until toggled back |

Once visible, the dock stays up while the pointer is over it and hides shortly
after the pointer leaves, or after the peek times out. Clicking an app dismisses
it.

## Keyboard

| Key | Action |
|---|---|
| `Super` | Peek the dock |
| `Super + A` | Cycle focus through every running window in dock order, switching workspace or monitor as needed |

## Managing apps

The dock shows the pinned list in `pinned.json`, next to this file:

```json
[
  "chromium",
  "org.wezfurlong.wezterm",
  "org.gnome.Nautilus"
]
```

Each entry may be a desktop-entry id, a startup class, or an app name; matching
is case-insensitive and ignores a leading `org.example.` prefix.

- **Remove:** right-click an app's icon in the dock (or edit the file).
- **Add:** add a line to the file (or use `omarchy-shell mushroom-dock pin <id>`).
- The file reloads live on save.

### Actions

| Input | Action |
|---|---|
| Left click | Focus the app (cycles its windows), or launch it |
| Right click | Remove the app from the dock |
| Middle click | Launch a new instance |
| Left click mushroom | Omarchy menu |
| Right click mushroom | Terminal |

## IPC

```bash
omarchy-shell mushroom-dock ping
omarchy-shell mushroom-dock peek      # peek (Super tap)
omarchy-shell mushroom-dock dismiss   # hide now
omarchy-shell mushroom-dock toggle    # pin open / return to auto-hide
omarchy-shell mushroom-dock pin <id>  # toggle a pin
omarchy-shell mushroom-dock refresh
```

## Super key binding

`~/.config/hypr/bindings.lua` contains:

```lua
o.bind("SUPER + SUPER_L", "Show dock", "omarchy-shell mushroom-dock peek")
o.bind("SUPER + A", "Cycle dock apps", "omarchy-shell mushroom-dock cycle 1")
```

The cycle cursor walks individual windows (not just apps), so an app with
several windows is visited once per window. It advances on every press and
re-seeds from the focused window when the running set changes, so it stays
predictable across cross-workspace jumps.

## Notes

- The dock is themed from the running theme's `colors.toml`/`shell.toml`, with
  the mushroom-grove accent family (`#e86f5a`, `#e5b65d`, `#9dbb6d`, `#72b39e`)
  used for the logo, focus ring and indicators.
- Growing icons extend above the resting pill (nothing is clipped); an
  invisible hit area covers that overflow so hover stays reliable.
- Enable/disable like any plugin: `omarchy plugin enable mushroom.dock` /
  `omarchy plugin disable mushroom.dock`. A plugin disabled and re-enabled in
  the same session keeps its surface; restart the shell to reload code changes
  to this `keepLoaded` plugin.
