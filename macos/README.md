# Playnite for Mac

A native SwiftUI game library and launcher added to the Playnite fork. Built and tested on Apple Silicon with macOS Tahoe 26. This is an independent native implementation, not the Windows WPF application running under Wine. The original MIT-licensed Windows source remains in `source/`.

## Install

Download the Apple Silicon ZIP from this fork's macOS release, extract **Playnite for Mac.app**, and move it into Applications. The build is ad-hoc signed, not Apple notarized. macOS may require you to use **System Settings → Privacy & Security → Open Anyway** for a downloaded build.

On this development Mac, the app is installed at `~/Applications/Playnite for Mac.app`.

## Use

- **Scan** imports installed Steam games, native Epic Launcher manifests, Heroic Epic/GOG manifests, and Mac games in standard game folders. Steam games on external disks are discovered through `libraryfolders.vdf`.
- **Add game → Add Mac application** adds a `.app` from any disk. **Add games folder** recursively finds applications in a game directory, up to five levels deep.
- Choose a game and press **Play**. Mac applications use `NSWorkspace.openApplication`; Steam, Epic, and Heroic use their installed client's launch protocol. Store ownership and DRM still apply.
- Covers, descriptions, developers, genres, and release dates are fetched from Steam when available. Games are matched by Steam app ID or one exact normalized title. Ambiguous results never overwrite metadata automatically.
- **Find metadata** lets you choose a Steam match or paste a game page from Steam, GOG, itch.io, or Epic. GOG and itch.io expose page metadata. Epic can block automated access; use the equivalent Steam title when that happens. Store pages expose different fields; missing fields are preserved.
- Favorites, search, recent launch requests, Finder reveal, JSON export/import, and library backups are included.

Default application search roots: `/Applications` (game category and recognized titles only), `/Applications/Games`, `/Applications/GOG Games`, `~/Applications`, `~/Games`, `~/GOG Games`, and `~/Library/Application Support/itch/apps`. Additional folders are remembered and can be removed in **Import and launch help**. An explicitly added folder is treated as a game folder, so all `.app` bundles within it are candidates.

## What this release supports

| Integration | Installed library import | Launch | Metadata |
| --- | --- | --- | --- |
| Native Mac apps | App picker and game-folder scan | macOS Launch Services | Automatic exact Steam match; store-page override |
| Steam | Local ACF/VDF manifests, external libraries | `steam://rungameid/ID` | Steam app details and search |
| Epic | Local `.item` manifests | Epic client URL | Exact Steam match; page override subject to store access |
| Heroic Epic / GOG | Local installed JSON manifests | `heroic://launch/RUNNER/ID` | Exact Steam match; GOG catalog fallback |
| GOG offline Mac games | Application/folder scan | Native `.app` | Steam matching or GOG store page |
| itch.io Mac games | Default apps folder or chosen folder | Native `.app` | Steam matching or itch.io store page |

No account credentials are requested or stored. This release imports installed games, not entire online account libraries. It does not download games, sync cloud saves, run Windows Playnite plugins/themes, or provide fullscreen/controller UI. It does not make Windows-only executables compatible with macOS. Heroic's configured compatibility runtime handles its Windows games. Local scans leave missing entries in the library so temporarily disconnected disks do not erase metadata.

A successful store URL handoff is recorded as a **launch request**, not proof of a running game. Direct native launch errors are shown in the app. Games can still have their own OS, runtime, DRM, or hardware requirements.

## Local data

`~/Library/Application Support/PlayniteMac/library.json` stores the library and scan folders. Atomic writes retain the previous save as `library.json.backup`. If the library cannot be decoded, the app preserves it and refuses to overwrite it. Restore the backup and restart. JSON import merges new IDs; it does not replace existing records. Export before moving the library between machines; installed paths may need re-adding.

Online metadata requests go directly to the relevant stores. Artwork is retrieved from provider image URLs. There is no telemetry server or embedded login. SteamDB is linked only as background context; it is not scraped and does not supply an open metadata API. Public store endpoints can change or rate-limit requests. Metadata failures are listed under **notices** and do not prevent game launches.

## Build and validate

Requires Swift 5.9+ and Apple's macOS SDK, from Command Line Tools or Xcode. macOS 14 is the deployment target; the local release is built for Apple Silicon and verified on Tahoe. Intel builds can be produced on an Intel Mac; Intel hardware has not been tested.

```sh
cd macos
swift run PlayniteValidation
swift run PlayniteValidation --live
./scripts/build-app.sh --install
open "$HOME/Applications/Playnite for Mac.app"
```

The standalone validation executable needs no XCTest installation. It checks VDF parsing, installation state, atomic persistence/backup behavior, metadata preservation, HTML/entity parsing, host restrictions, Epic launch URLs, and title matching. `--live` also checks Steam search/details and GOG/itch.io pages. These are network integration checks and depend on store availability. A release build prints the bundled `.app` and creates a ZIP in `dist/`.

```sh
./dist/Playnite\ for\ Mac.app/Contents/MacOS/PlayniteMac --diagnostics
```

Diagnostics print the discovered games as JSON without launching games or modifying the library. Paths and game names appear in the output; inspect before sharing.

See [VALIDATION.md](VALIDATION.md) for the exact local test results and untested integrations.
