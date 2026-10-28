# Playnite Carousel — shared desktop edition

A redesigned, lightweight game-library UI for Windows, Linux, and macOS. Rust handles local library data, discovery, launching, uninstall handoffs, and metadata. The frontend uses the OS webview, seven reusable carousel slots (five visible), and transform-only movement. It bundles no Node.js runtime, Chromium runtime, or frontend component framework.

The optimized SwiftUI application in `../macos` remains the native Mac edition. The shared edition provides the same core library workflow on all three desktop systems, with platform-specific launch and uninstall behavior.

## Install / build

Download the installer/package for your OS from this fork's releases. Windows uses WebView2; Linux uses WebKitGTK 4.1. See [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/) for build dependencies.

```sh
npm ci
npm test
npm run build
cargo test --manifest-path src-tauri/Cargo.toml --locked
npm run tauri -- build
```

Platform CI builds a Windows NSIS installer, Linux DEB/AppImage, and shared macOS app. Native Mac builds use `../macos/scripts/build-app.sh`. Installers are unsigned previews; native-client/gameplay validation is distinct from compilation and automated tests.

## Library and controls

Installed Steam games are detected at startup on Windows, Linux (including the Flatpak Steam location), and macOS. Heroic/Epic installation manifests and native Mac game bundles are also read. Add a game application directly or add a games/Wine-prefix folder to include another location. Linux game-category `.desktop` entries and AppImages are supported. Detection never installs a runtime or rewrites Steam, Wine, or wrapper configuration.

Left/Right or A/D browses continuously, Enter launches directly, Shift toggles details, L toggles libraries, F toggles favorites, and Escape closes panels. Command/Ctrl-F focuses search; Command/Ctrl-R or the Scan action detects installations again. Both sidebars start hidden. Navigation pauses in forms and dialogs. Connected standard-mapped controllers use the D-pad/stick or shoulders to browse, bottom face button to play, top for details, left for libraries, and right to close panels. Polling stops while the window is inactive or hidden.

Portrait covers, landscape inspection images, and alternate backgrounds are independent cached roles. Aspect-ratio validation rejects a wide banner as a portrait candidate. Steam 2× and standard portrait candidates are tried, with local cache hits preferred. The image renderer reads only cached files and fits cover art without cropping. A missing role uses the last cached fallback. Background changes are debounced to avoid decoding every intermediate selection during fast navigation.

Metadata matching supports Steam, GOG, itch.io and publisher pages, plus bundled metadata for Roblox, VALORANT, Genshin Impact, Honkai: Star Rail, Zenless Zone Zero, League of Legends, and Minecraft. Hiding a game keeps its metadata. Library import/export, favorites, recent launch history, notices, and metadata cancellation are included.

## Wine, CrossOver, Sikarugir, and Kaon

Wine Steam discovery reads `drive_c/Program Files (x86)/Steam`, `drive_c/Program Files/Steam`, and their `libraryfolders.vdf` files. Windows drive paths are resolved through the existing prefix and `dosdevices` links. Each prefix gets a distinct game ID and launch plan, so the same Steam ID in native Steam and two prefixes stays distinguishable.

Default search includes `~/.wine`, CrossOver bottles, Whisky bottle locations, and Sikarugir/Wineskin game bundles. Add a custom prefix folder to include a nonstandard installation. A Sikarugir bundle keeps its bundled Wine executable and prefix; native game wrappers continue to launch through macOS. CrossOver routes retain their bottle identity. A missing runtime produces a clear error rather than routing the game through the wrong Steam client.

[Kaon's reference launcher](https://github.com/natbro/kaon/blob/main/scripts/launch_crossover.sh) demonstrates prefix/bottle-bound Wine launching. Existing Kaon-modified native Steam libraries remain native Steam entries; their existing Steam launch configuration stays responsible for redirection. Playnite does not install Kaon hooks or edit `steam_dev.cfg`. The wrapper's custom bootstrap scripts and proprietary runtime behavior are not reimplemented. Real clients, credentials, game runtimes, and anti-cheat compatibility still determine whether an individual game runs.

## Uninstall and data

Mac `.app` bundles and standalone Linux AppImages can be moved to Trash after confirmation. Data inside a moved bundle moves with it; external saves remain. Steam opens its uninstall dialog. Wine Steam opens that dialog inside the original prefix. Epic/Heroic open their client. Windows standalone installations open Installed Apps; Linux package-managed entries use the original package/system manager. The app does not delete an executable and claim the whole installation is uninstalled. Metadata stays until a successful Trash operation or a later scan confirms the installation is gone. Temporarily disconnected volumes do not count as removal.

The shared edition stores data in the OS application-data directory under `PlayniteCarousel`. On macOS, the first run copies an existing native `PlayniteMac` library and its media cache into the separate shared-edition directory. The two editions do not concurrently write the same library file. Atomic writes keep `library.json.backup`; invalid libraries enter read-only mode and are preserved.

Development variables: `PLAYNITE_DATA_DIRECTORY` isolates a library, and `PLAYNITE_OFFLINE=1` disables network requests while allowing cache hits. `playnite-carousel --diagnostics` prints discovered installations without launching games. Inspect paths/game names before sharing diagnostic output.

See [the audit](../AUDIT.md) and [validation record](../macos/VALIDATION.md) for measurements, completed fixes, and platform/hardware limits. A universal lower-memory claim against upstream requires a like-for-like benchmark; the lightweight design claims refer to the implementation and measured artifacts.
