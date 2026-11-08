# Mushroom Grove Dashboard

A weather + news home page for the Omarchy shell, living on its own `home`
workspace. It shows through to the theme wallpaper, which drifts and breathes
behind it, and it opens on login.

## Features

- **Home workspace.** `home` is a named Hyprland workspace shown as a mushroom
  tab at the far left of the bar's workspace strip (before `1`). Toggle it with
  `Super + H` or the tab; it opens automatically on login.
- **Animated wallpaper.** The current theme background is warped by a slow
  swirl (vortex) shader on the home workspace, so the art drifts and twists
  behind the cards. Only the home workspace animates.
- **Idle daydream.** After 15 seconds with no input, the whole dashboard fades
  away and the swirl speeds up, leaving just the artwork; any input brings it
  back.
- **Transparent glass cards.** The weather and news panels are near-transparent,
  borderless, sharp-cornered glass with a soft shadow and a hairline top
  highlight, so the artwork stays the star. The news list scrolls fluidly
  (taps use a `TapHandler`, so drags and flicks reach the list).
- **Weather** from wttr.in: current conditions, feels-like, humidity, wind,
  pressure, plus a four-day forecast. Uses the location configured by
  `omarchy-weather-location`; with none set it auto-detects from the IP.
- **Newsfeed.** Hacker News comes from the official Firebase API (`hn.py`), so
  its order matches news.ycombinator.com exactly; BBC World, Ars Technica and
  The Verge come from their RSS/Atom feeds, fetched in parallel. Sources are
  interleaved round-robin (HN, BBC, Ars, Verge, HN, BBC, …) so each keeps its
  own order, de-duplicated by title. Click a headline to open it.
- **Source filter tiles.** A row of tiles above the list — All, Hacker News,
  BBC World, Ars Technica, The Verge — filters the panel to one source. The
  active tile is accent-highlighted; tapping it again (or All) clears it.
- **Greeting + clock** in the header, with relative timestamps on stories.
  Hacker News stories carry points/comments in `news[]` for future use.

## Opening it

| Trigger | Effect |
|---|---|
| `Super + H` | Toggle between `home` and your previous workspace |
| Mushroom tab in the bar | Go to `home` |
| Login | Opens automatically (`~/.config/hypr/autostart.lua`) |

## IPC

```bash
omarchy-shell mushroom-dashboard toggle
omarchy-shell mushroom-dashboard show
omarchy-shell mushroom-dashboard hide
omarchy-shell mushroom-dashboard refresh
omarchy-shell mushroom-dashboard ping
```

## Configuration

- **Feeds / sources:** edit `feeds` in `DashboardModel.js` for the RSS sources;
  Hacker News is handled by `hn.py` (official API, `LIMIT` stories).
- **Location:** set it with `omarchy-weather-location`; the state file is read
  live.
- **Card transparency:** the two card `gradient` alphas in `DashboardWindow.qml`
  (currently `0.30` → `0.38`) control how much wallpaper shows through, and
  `contentOpacity` (idle) controls the fade.
- **Wallpaper motion:** the swirl lives in `vortex.frag` (compiled to
  `vortex.frag.qsb` with `qsb --qt6`). The `strength` property sets the twist
  and the swirl speed is the timer step in `DashboardWindow.qml` (`0.033` idle,
  `0.10` while active).
- **Idle timeout:** `timeout: 15` on the `IdleMonitor` in `Dashboard.qml`.
- **Refresh:** weather and news refresh when home opens and every 15 minutes.

## Notes

- The dashboard is a `keepLoaded` panel plugin: one full-screen layer surface
  per monitor, mapped only while the `home` workspace is focused. It sits on the
  Bottom layer, above the wallpaper and below the bar and windows. Code changes
  need `omarchy restart shell`.
- The bar tab comes from the `mushroom.workspaces` clone of the workspaces
  widget (`~/.config/omarchy/plugins/mushroom.workspaces/`), which adds the
  mushroom button as the first cell so it never overlaps the numbered
  workspaces.
