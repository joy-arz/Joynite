# Playnite for Mac

A native SwiftUI library and launcher in this Playnite fork. The Mac application lives in `macos/`; the original MIT-licensed Windows source remains in `source/`.

## Install

Download the Apple Silicon ZIP from [this fork's releases](https://github.com/joy-arz/Playnite/releases), unzip **Playnite for Mac.app**, and move it into Applications. Builds are ad-hoc signed, not Apple notarized. Downloaded copies may require **System Settings → Privacy & Security → Open Anyway**.

On the development Mac, the app is installed in `~/Applications/Playnite for Mac.app`. macOS Tahoe on Apple Silicon is tested; the deployment target is macOS 14.

## The carousel

Five cards form a continuously wrapping carousel. The selected card is centered and largest, with its title and description inside. Cards further from the center become smaller. A one-game library displays one card; small multi-game libraries repeat entries to maintain the five-slot loop. Choose a card, use the arrows, swipe/drag horizontally, or scroll a trackpad horizontally.

Steam portrait covers are preferred over wide banners. A different game screenshot supplies the backdrop when available. If a provider has no alternate image, the cover or local icon is used instead. Both sidebars start hidden; their header buttons toggle them.

| Keyboard | Action |
| --- | --- |
| Left / Right or A / D | Previous / next game, wrapping at both ends |
| Return | Launch selected game immediately |
| Shift | Toggle game details |
| L | Toggle library sidebar |
| F | Toggle favorite |
| Escape | Close sidebars |
| Command-F | Focus search |
| Command-N | Add Mac application |
| Command-R | Scan installed games |

Navigation shortcuts pause while typing, or while a sheet/dialog is open. Return in search and metadata forms does not launch a game. Shift inside a text field retains normal typing behavior.

Controllers supported by Apple's extended Game Controller profile are detected at connection/disconnection. D-pad or left stick browses with hold-to-repeat; shoulders also browse. Bottom face button launches, top face button toggles details, left face button toggles libraries, and right face button closes panels. Right-stick click toggles favorite. Hints switch on actual keyboard/mouse/controller use and use the connected controller's symbol names. Input is handled only while Playnite is active, so it does not intercept game controls. Physical controller compatibility depends on macOS and the device; see validation notes.

## Import and metadata

**Add / manage → Scan installed games** discovers Steam ACF/VDF libraries, external Steam libraries, Epic `.item` manifests, Heroic Epic/GOG installed JSON, and native Mac applications. **Add Mac application** adds a game from any disk; **Add games folder** remembers a directory and scans up to five levels deep. Wine-wrapped `.app` games are detected through their prefix directories.

Standard scan roots: `/Applications` and `~/Applications` (game categories, recognized titles, and wrappers), `/Applications/Games`, `/Applications/GOG Games`, `~/Games`, `~/GOG Games`, and `~/Library/Application Support/itch/apps`. Explicit game folders treat all `.app` bundles as candidates. Hidden games can be restored from the Library menu.

Steam metadata uses an app ID or one exact normalized title. Ambiguous matches are left for **Find metadata**, which can select a Steam result or import a Steam/GOG/itch.io/Epic page. GOG catalog search is a fallback. SteamDB is not scraped. Public store endpoints can change or rate-limit requests; errors never discard existing metadata or stop local game launches.

A publisher catalog contains offline descriptions, developers, and genres for Roblox, VALORANT, Genshin Impact, Honkai: Star Rail, Zenless Zone Zero, League of Legends, and Minecraft. Exact aliases automatically match installed applications. **Library → Publisher metadata catalog** can apply one to the selected entry. Official publisher artwork is retrieved when exposed by the page; missing artwork falls back to the local application icon. Adding metadata does not install a game or make unsupported games run on macOS.

## Offline retention

Metadata lives in `~/Library/Application Support/PlayniteMac/library.json`. Covers and alternate backgrounds are downloaded, validated, resized to a maximum dimension of 1920 pixels, and saved as PNGs under `Media/<game-id-hash>/`. The library stores their cache keys. Rendering reads local files, so already cached artwork and metadata remain usable offline and across restarts. Remote failures preserve the last successful files. Existing 0.1 records migrate without losing favorites, launch history, or descriptions.

**Hide from library** keeps the record and cache. Missing external disks do not trigger cleanup. An explicit refresh can update metadata; it does not erase valid fields when a response omits them. Text exported as JSON remains portable; the image cache stays on its originating Mac and can be repopulated online on a new Mac.

Library saves are atomic and retain the previous version as `library.json.backup`. A corrupt library is preserved and not overwritten. Restore a backup and restart if necessary. Export a library before moving machines; launch paths may need re-adding. No credentials or telemetry server are used.

## Uninstall

Use **Uninstall…** in game details or the card context menu.

- A native `.app` is moved to Trash after confirmation. Data inside its bundle moves with it, including saves embedded in a Wine wrapper. External save files are left alone. The library entry and image cache are removed only when the move succeeds. Restore from Trash if needed.
- Steam opens `steam://uninstall/ID`; complete or cancel the dialog in Steam.
- Epic/Heroic open their client; use that client's Uninstall command. These clients do not provide a common supported uninstall URL, so Playnite does not bypass their installation records.
- For store handoffs, cached metadata stays until a return to Playnite or a scan confirms the game path is gone and its parent is accessible. Disconnected volumes never count as removal. Cancelled or failed operations keep cached metadata.

Running native applications must be quit first. System apps, symlinks, nested application bundles, and Playnite itself are protected from the native Trash action.

## Launch support and limits

Mac applications launch with macOS Launch Services. Steam, Epic, and Heroic installations use their installed client's protocol. Store ownership and DRM still apply. A successful request is recorded as a **launch request**, not proof of reaching a main menu.

This release imports installed games, not entire online account libraries. It does not download games, sync cloud saves, run Windows Playnite plugins/themes, or include a Windows compatibility runtime. Heroic uses the runtime configured there. Individual games still have their own OS, hardware, runtime, and anti-cheat requirements.

## Build and validate

Requires Swift 5.9+ and Apple's macOS SDK from Command Line Tools or Xcode. XCTest is not required.

```sh
cd macos
swift run PlayniteValidation
swift run PlayniteValidation --live
PLAYNITE_OFFLINE=1 swift run PlayniteValidation
./scripts/build-app.sh --install
open "$HOME/Applications/Playnite for Mac.app"
```

The build script produces an optimized `.app` and a versioned ZIP in `dist/`. GitHub CI validates core behavior and packages the app. Intel builds can be produced on Intel Macs but are untested.

Development/validation environment variables: `PLAYNITE_DATA_DIRECTORY` selects a separate library directory; `PLAYNITE_OFFLINE=1` disables metadata and artwork network requests while allowing existing disk-cache hits. These allow isolated offline/uninstall tests without touching real libraries or games.

`PlayniteMac --diagnostics` prints discovered games as JSON without launching games or changing the library. Paths and game names appear in that output; inspect before sharing it. See [VALIDATION.md](VALIDATION.md) for observed checks and remaining hardware/provider limitations.
