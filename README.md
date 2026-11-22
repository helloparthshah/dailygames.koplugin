# Daily Games for KOReader

NYT Wordle, Connections, Strands, Mini and Daily Crossword, plus the Krillion daily dive, built for e-ink.

## Install

- **ZenPM (recommended):** open ZenPM > **Sources**, add
  `https://raw.githubusercontent.com/helloparthshah/dailygames.koplugin/main/zenpm/`,
  refresh, then install **Daily Games** (Games). ZenPM offers updates for new releases.
  From a terminal: `zenpm repo add dailygames <url> && zenpm repo refresh && zenpm install dailygames`.
- **Manual:** download `dailygames.koplugin.zip` from [Releases](https://github.com/helloparthshah/dailygames.koplugin/releases), unzip, and copy the `dailygames.koplugin` folder into `koreader/plugins/` (ZenFM or USB).

Restart KOReader afterwards. Remove any older NYT Games plugin folder so you don't have both.

## Open

- **Tools > Daily Games**: hub, each game, Krillion options, NYT-S cookie.
- **ZenOS App Launcher:** "Daily Games" is added automatically the first time KOReader starts with the plugin (ZenPM installs are added by ZenOS itself). Remove it from the launcher and it stays removed.
- Gestures: actions **Daily Games hub** and **Daily Games: <game>** (General section).

Progress for each game is saved per day, so you can leave and come back.

## Games

| Game | Notes |
| --- | --- |
| Wordle | Black = right spot, gray = wrong spot, white = not in word. Keys: `■A` right, `[A]` wrong spot, `·A·` not in word. |
| Connections | Board in NYT order. Shuffle, deselect, "one away", repeat-guess check, groups revealed when out of mistakes. |
| Strands | Tap adjacent letters (diagonals ok). Tap the last letter to undo. Words only count in their real position. `[A]` selected, `(A)` found, `*A*` spangram, `{A}` hint. |
| Crosswords | Tap a square to select it, tap again to switch Across/Down. Current word is shaded. Clues list jumps to a clue. Check offers to clear wrong letters. |
| Krillion | Seven prompts, 25 s each, scored by krillion.io. Timer can be turned off. |

The Daily Crossword needs an NYT subscription: set your `NYT-S` cookie under **Tools > Daily Games**. The Mini works without it.

## Code layout

```
main.lua                  menu, hub, dispatcher actions
dailygames/http.lua       JSON over HTTPS (LuaSocket/LuaSec)
dailygames/store.lua      settings + per-day progress (settings/dailygames.lua)
dailygames/ui.lua         FullscreenApp base class, tiles, banners, messages
dailygames/nyt.lua        NYT fetchers, normalized data
dailygames/wordle.lua
dailygames/connections.lua
dailygames/strands.lua
dailygames/crossword.lua
dailygames/krillion.lua
dailygames/zenos.lua      ZenOS App Launcher entry
```

To add a game: create `dailygames/<game>.lua` with a `launch()` function (subclass `UI.FullscreenApp` for a full-screen board) and add an entry to `GAMES` in `main.lua`.

## Development

Tests run against stubbed KOReader modules:

```sh
for t in tests/test_*.lua; do luajit tests/run.lua "$t"; done
```

To release, push a tag like `v1.0.1`, or run the **Release** workflow from the Actions tab with a version. It runs the tests, attaches `dailygames.koplugin.zip` to the release, and regenerates the ZenPM source in `zenpm/` (`.github/scripts/zenpm_manifest.py`).
