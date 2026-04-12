# Gharka Bars

Stock nameplates are fine right up until you actually need them.

`Gharka Bars` replaces the chaos with clean overhead raid bars that stay readable, clickable, and useful when the screen turns into a small civil war.

## What It Does

- replaces stock-style overhead clutter with custom HP and MP bars
- keeps bars anchored to the correct unit
- supports `player`, `target`, `watchtarget`, and raid members
- shows role markers, distance text, and target highlighting
- tracks CC icons and timers directly on the bar
- includes an in-game `GB` settings window with layout, text, color, and CC controls
- supports local settings backups and import from the latest backup

## Install

1. Drop the `gharka-bars` folder into your AAClassic `Addon` directory.
2. Make sure the addon is enabled in game.
3. Reload the UI if needed.
4. Click the `GB` button to open settings.

Saved settings live in `gharka-bars/.data` so normal addon updates do not stomp your configuration.

## Quick Start

1. Click `GB`.
2. Enable the addon if it is not already on.
3. Open the `Layout`, `Text`, `CC`, and `Colors` pages to tune the bar style.
4. Save a backup once you have a setup you like.

If you break your masterpiece, `Import` pulls the latest backup back in without requiring interpretive dance.

## How To

### Basic Use

- `player`, `target`, and `watchtarget` bars update aggressively for accuracy
- raid bars use a lighter background schedule to keep overhead down
- clicking a bar targets that unit when the client exposes a valid targeting path

### Settings

Use the `GB` window to adjust:

- general behavior
- bar layout and spacing
- text sizes and limits
- CC icon display
- color groups for health, mana, text, and borders

The settings window also includes:

- `Backup`
- `Import`
- style reset
- full reset

### CC Tracking

CC icons and timers can be attached directly to each custom bar. This keeps the important information where your eyes already are instead of floating off into the wilderness.

### Performance

Recent updates focused on reducing redundant widget work and smoothing raid-time scheduling while keeping bar accuracy intact. The goal is simple:

- bars stay locked to the right unit
- HP and MP remain current
- targeting and highlights stay correct
- the addon wastes less frame time doing the same work twice

## Notes

- `watchtarget` and target-of-target behavior still depends on what the client exposes at runtime.
- The addon keeps backup files under `.data/backups`.
- If something feels off after a major update, try one reload before blaming the addon, the API, or fate.

## Version

Current version: `1.5.40`
