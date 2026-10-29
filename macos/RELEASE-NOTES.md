## Joynite 0.4.0

- Rename the app, executable, package, repository, installer labels, and current documentation to Joynite. Original upstream code and license attribution remain intact.
- Copy previous metadata, cached images, favorites, custom overrides, and history into the new data directories without deleting the previous library. Existing Joynite data takes priority on later launches.
- Add an opt-in launch-at-login setting on macOS, Windows, and Linux. Native macOS uses SMAppService, while the shared edition uses Tauri autostart with stable AppImage paths. The setting starts off.
- Add the orange Ko-fi cup in the bottom-right footer and Settings, linking to https://ko-fi.com/joyarz. There is no embedded support widget or background donation-page request.
- Update the README with actual Inscryption-centered carousel/details screenshots, a settings screenshot, support links, and joy-arz maintainer credit. GitHub’s contributor API already attributes the fork’s commits to joy-arz.

## Joynite 0.3.0

- Longer interruptible sliding, stable positional identities, nine buffered cards with five visible, off-thread image decoding, and a bounded native image cache. Rapid input retargets current motion instead of queuing animations.
- Separate portrait, inspection, and alternate backdrop caches. Complete foreground artwork stays visible over a softened fill, including wide Roblox artwork. Small uploads are not enlarged during caching.
- Custom metadata and all three image roles can be edited offline. Per-field overrides survive provider refresh; reset restores the latest automatic data. Imported files are copied into the managed cache.
- New application icon and header mark preserve the supplied vector geometry with a contrasting yellow/orange gradient on charcoal.
- Steam inside Wine, CrossOver, and Sikarugir/Wineskin keeps prefix-specific runtime/arguments for launch and uninstall. CrossOver environment and Sikarugir runtime detection follow their respective installation layout; no client settings are rewritten.
- Startup discovery now runs for existing libraries too. Command-R remains available for manual scans. Toolbar focus uses orange instead of the native blue ring.
- A separate Rust/system-webview edition supports Windows, Linux, and macOS. The native SwiftUI edition remains available for Mac. Existing libraries retain cached metadata, favorites, and launch history.
- Audit fixes include stale snapshot rejection, process reaping, read-only guards, drag-click suppression, bounded image decoding, and fewer redundant writes. See AUDIT.md for measurements and validation limits.

Apple Silicon native builds are ad-hoc signed, not notarized. Platform builds and fixture tests do not establish game/anti-cheat compatibility or physical controller support for every device.

## Joynite 0.2.0

A black-and-orange, controller-ready carousel with persistent offline metadata.

- Five large cards wrap continuously. The selected game is centered and enlarged; titles and descriptions live inside the cards.
- Steam portrait covers are preferred, with cached banners/icons as fallback. A separate screenshot becomes the backdrop where available.
- Both sidebars start hidden. Left/Right or A/D browse, Return launches directly, Shift toggles game details, L toggles libraries, F toggles favorites, and Escape closes panels. Search fields retain normal text editing.
- Connected extended controllers use D-pad/left stick and shoulders to browse, bottom face button to launch, top face button for details, left face button for libraries, and right face button to close panels. On-screen hints use controller-provided glyphs and follow the active input.
- Metadata text, covers, and backgrounds persist on disk. Already cached images need no network access. Hide retains metadata; Restore hidden games brings entries back.
- Native uninstall moves the selected application bundle to Trash after confirmation, including any data inside the bundle. Metadata/cache cleanup happens after success. Steam opens its uninstall dialog. Epic and Heroic open the client for its own uninstall command; cleanup waits for confirmed removal. Disconnected disks do not count as uninstall.
- Publisher catalog adds Roblox, VALORANT, Genshin Impact, Honkai: Star Rail, Zenless Zone Zero, League of Legends, and Minecraft. Descriptions are bundled; publisher artwork is cached when available. Metadata does not imply macOS compatibility.

Existing 0.1 libraries migrate without losing metadata, favorites, or launch history. The app remains an independent native implementation in this fork, with no Windows plugin compatibility or built-in Windows runtime. Epic store pages may block automated access. This Apple Silicon preview is ad-hoc signed, not Apple notarized.
