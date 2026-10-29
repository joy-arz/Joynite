# Joynite — shared desktop edition

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

[Kaon's reference launcher](https://github.com/natbro/kaon/blob/main/scripts/launch_crossover.sh) demonstrates prefix/bottle-bound Wine launching. Existing Kaon-modified native Steam libraries remain native Steam entries; their existing Steam launch configuration stays responsible for redirection. Joynite does not install Kaon hooks or edit `steam_dev.cfg`. The wrapper's custom bootstrap scripts and proprietary runtime behavior are not reimplemented. Real clients, credentials, game runtimes, and anti-cheat compatibility still determine whether an individual game runs.

## Uninstall and data

Mac `.app` bundles and standalone Linux AppImages can be moved to Trash after confirmation. Data inside a moved bundle moves with it; external saves remain. Steam opens its uninstall dialog. Wine Steam opens that dialog inside the original prefix. Epic/Heroic open their client. Windows standalone installations open Installed Apps; Linux package-managed entries use the original package/system manager. The app does not delete an executable and claim the whole installation is uninstalled. Metadata stays until a successful Trash operation or a later scan confirms the installation is gone. Temporarily disconnected volumes do not count as removal.

The shared edition stores data in the OS application-data directory under `JoyniteDesktop`. On macOS, the first run copies an existing native `Joynite` library and its media cache into the separate shared-edition directory. The two editions do not concurrently write the same library file. Atomic writes keep `library.json.backup`; invalid libraries enter read-only mode and are preserved.

Development variables: `JOYNITE_DATA_DIRECTORY` isolates a library, and `JOYNITE_OFFLINE=1` disables network requests while allowing cache hits. `joynite --diagnostics` prints discovered installations without launching games. Inspect paths/game names before sharing diagnostic output.

See [the audit](../AUDIT.md) and [validation record](../macos/VALIDATION.md) for measurements, completed fixes, and platform/hardware limits. A universal lower-memory claim against upstream requires a like-for-like benchmark; the lightweight design claims refer to the implementation and measured artifacts.

## Custom metadata and artwork

From game details choose **Edit metadata and images…**, or use Add / manage → Edit selected metadata / images. Title, developer, release date, genres, and description are independent local overrides. Choose a portrait card cover, horizontal inspection image, and alternate background. PNG, JPEG, WebP, and GIF uploads up to 24 MB are copied into the offline cache. Files above 8192 pixels per dimension or the decode allocation limit are rejected. Animated files use their first frame. Automatic refresh preserves overrides; restore automatic text or reset each image separately from the editor. Export includes metadata and override keys; copy Media too when transferring custom images.

Nine card nodes retain five visible cards plus offscreen buffers. A 380 ms transform transition can be interrupted by further input without queuing old moves. Full foreground images fit their frames; a cached 64-pixel softened copy fills unused space. No live full-resolution blur runs during movement. Reduced-motion preferences disable transitions.

The orange/yellow logo derives from the supplied vector geometry. Rebuild shared assets with `npm run brand`; icons are stored in src-tauri/icons. The application uses the installed system webview and does not bundle a browser or Node runtime.

## Launch at login and support

Settings includes **Launch Joynite when I sign in**, off by default. Windows uses the current user’s startup registration, Linux uses an XDG autostart entry (AppImages retain their original executable path), and macOS uses its login/startup mechanism. No administrator service is installed. Moving the app after enabling startup may require disabling and re-enabling the setting.

The orange Ko-fi cup in the bottom-right footer opens https://ko-fi.com/joyarz in the default browser. Opening Joynite does not load a donation widget or make a support-page network request.

Joynite migrates earlier libraries without deleting their originals. Legacy data directory names and environment-variable aliases remain only for migration/backward compatibility. Original upstream code and licensing still refer to Playnite.

## Quiet software updates

A background check runs after startup without blocking your library. A new official release appears in a small top-right notice. Update now downloads and verifies the signed package before installation. Update later snoozes that version for 24 hours. Don’t remind me again skips only that version; newer releases can notify again. Offline failures stay silent. Settings includes a manual check. Libraries, cached artwork, and game installations are not replaced by app updates. Version 0.4 needs one manual install of 0.5 to gain this feature. See ../updates/README.md and ../IMPROVEMENTS.md.

## Search and portable backups

Press Space or Command/Ctrl-F for the expanding center search. Enter selects the best match and returns to the carousel. Matching ignores case/accents and tolerates misspellings; suggestions stay within the active library filter. Escape cancels. Library Tab traversal is disabled; dialog forms keep normal focus behavior. Large-library queries run in a Web Worker, and stale results are discarded.

Add / manage provides **Back up library and images** and **Restore library backup**. ZIP backups include metadata and available cached/custom images with a versioned SHA-256 manifest. Restore validates all entries before merging and preserves existing edits. Legacy JSON imports remain supported. Launch paths can need re-adding on another computer.

The bundled project catalog also recognizes EDOPro / Project Ignis, YGOPro, legacy YGOPro Percy, YGOPro 2, KoishiPro, YGO Omega and MDPro3. Matching is exact after case/punctuation normalization, with explicit executable and launcher aliases. Project descriptions work offline; downloaded artwork remains in the existing cache. Custom text/images take precedence.

## Startup ranking and follow-up improvements

Joynite records successful launch requests locally as launchCount. It never queries store playtime or OS launch histories for this statistic, and legacy records start at zero. Favorites rank ahead of other games; launch count then title/ID break ties. Startup shows ranks 4, 2, 1, 3, 5 around the center, and remaining ranks continue rightward around the infinite carousel. A session keeps its initial counts for ordering, so playing does not suddenly reshuffle cards. The count is visible in details and included in backups.

Search supports Up/Down suggestion selection and uses fuzzy results only when direct matches are absent. Metadata hydration emits changed-record patches instead of a complete snapshot per game; stale patches cannot resurrect deleted records. Complete snapshots remain for initial load and explicit library operations.

Backup progress/cancel controls run independently of the library mutex. Cancellation before the restore commit rolls back newly copied artwork. **Preview backup** verifies a ZIP and reports added/kept games without applying it. Destination write permissions and cross-machine game paths can still differ. Launch details read a small local report for processes/handoffs initiated by Joynite; no external game-usage history feeds the ranking.
