# Joynite validation record

## Version 0.4.0 — 2026-10-29

The Joynite rename builds successfully on Apple Silicon/macOS Tahoe. Live core validation passes **145 assertions, 0 failures**. The shared Rust backend passes **15 tests**, including migration idempotence, original-library preservation, cached media copying, and legacy/new launcher identity guards.

The installed native Joynite app migrated the existing six-game library and cached artwork from the prior PlayniteMac data directory. The original library remains intact. Native UI checks verified Joynite title/menu/header branding, the orange Ko-fi cup and exact support URL, Inscryption centered in the carousel, and the metadata panel. Actual screenshots of these views are committed in docs/screenshots.

The native Settings window started with launch-at-login off. Enabling it registered successfully through SMAppService and showed on; disabling it unregistered successfully and returned to off. The setting was left off. This validates registration state, not a machine reboot.

Shared startup uses Tauri autostart 2.7.0 with explicit permissions for status, enable, and disable. Its Linux AppImage path handling was checked in the installed plugin source. Platform build results and shared UI checks are recorded with the release. No real game was uninstalled during this rename.

Previous validation history follows. Names in earlier records describe the predecessor versions; original artifacts remain available under their original tags.


## Version 0.3.0 — 2026-10-28

Native release packaging succeeds on Apple Silicon/macOS Tahoe. Live validation passes **136 assertions, 0 failures**; forced-offline validation passes **126 assertions, 0 failures**. Additional coverage includes two independent Sikarugir Steam prefixes with the same app ID, original runtime/argument preservation, compatibility uninstall routes, Windows-path traversal rejection, three artwork aspect roles, persistent custom text/image keys, per-field override preservation across provider refresh, automatic reset, and custom image retention after deleting its source.

The shared Rust backend passes 13 tests and the JavaScript navigation model passes 5 tests (20,000 positions, wrapping and stable buffered identities). The prior checkpoint produced Windows NSIS, Linux DEB/AppImage, and macOS shared-app artifacts in CI. Windows and Linux CI builds passed for the final shared application code. Both macOS editions built locally and passed strict ad-hoc signature verification; hosted macOS jobs were queued during packaging.

A disposable copy of the real six-game library runs with JOYNITE_OFFLINE=1. Native UI checks verified the new logo, orange toolbar focus, five visible cards, uncropped foreground over softened fill, and saving a custom Roblox developer and cover from the editor. The custom Roblox developer and image survived an offline restart. Reset custom text and Use automatic restored the cached publisher data. Shared UI checks verified a saved developer override and twelve rapid Right-arrow presses wrapping to the same selected index. Changes are confined to /tmp validation data. No real game was uninstalled.

No numeric FPS or universal performance comparison is claimed from these checks. See ../AUDIT.md for findings and remaining controller/client validation limits.

## Version 0.2.0 — 2026-10-28

Environment: Apple Silicon, macOS Tahoe 26.6 (Darwin 25.6.0), Swift 6.3.1, Command Line Tools SDK 26.4. Deployment target: macOS 14.

### Automated checks

`swift run --package-path macos JoyniteValidation --live`: **102 assertions, 0 failures.**

`JOYNITE_OFFLINE=1 macos/.build/debug/JoyniteValidation`: **92 assertions, 0 failures.** Network requests are explicitly disabled in this mode; existing disk-cache hits still work.

Coverage:

- Nested VDF, escaped paths, malformed records, Steam installation-state bitmasks, and path checks.
- Atomic persistence, previous-save backups, corrupt-library preservation, and decoding 0.1 records without new optional fields.
- Metadata updates preserve launch identity and non-empty fields. Cached image keys and hidden state survive serialization.
- Steam metadata parsing, store HTML/entity parsing, HTTPS/host checks, and live Steam/GOG/itch.io responses.
- Five carousel slots, empty/single-game libraries, negative indices, forward/backward wrap, large repeated offsets, and safe Steam portrait URLs.
- Publisher catalog aliases and complete bundled descriptions/developers without network access.
- Native and Steam uninstall plans, rejected mismatched paths/IDs, pending-uninstall checks, and disconnected-volume retention.
- Image files survive a new cache instance and are retrieved with an unreachable source hostname. Invalid cache paths are rejected. Cleanup for one game leaves another game's images intact.

### Native UI checks

- Opened the black-and-orange build with both sidebars hidden and five visible cards.
- Verified Left/Right changes the selected game and wraps from the first entry to the final entry.
- Verified the Shift modifier reveals the selected game's details. The automation API cannot emit a standalone modifier, so the check used Shift+F12 to exercise the Shift transition.
- Verified existing descriptions, favorites/launch history fields, and installed entries survived upgrade. A separate pre-upgrade JSON snapshot was retained locally.
- Steam portrait-cover URLs for the installed titles returned HTTP 200. Alternate Steam screenshots were downloaded into the persistent image cache.

### Isolated offline and uninstall exercise

A separate application bundle used `JOYNITE_DATA_DIRECTORY` for a disposable one-game library and `JOYNITE_OFFLINE=1` to disable network requests. Its only application was a newly created test fixture. The fixture did not contain user game data.

1. Opened the isolated app and observed its saved description, cover, background, and Saved offline indicator with networking disabled.
2. Pressed Return while details were hidden. The fixture wrote its launch marker and the library recorded the successful launch callback. No metadata panel opened.
3. Opened Uninstall, verified the confirmation named the fixture's exact `.app` path, and cancelled. Confirmed the application, library record, and both cached image files remained.
4. Reopened Uninstall and selected Move to Trash. Observed the empty library with the successful uninstall status. Confirmed the original application path, record, and both cached image files were gone.
5. Closed the validation app and removed its temporary library/bundle. Removed only the temporary fixture record introduced during earlier UI setup from the real library. Real game installations and save files were not uninstalled.

### Limits

Physical controller hardware was not available for end-to-end testing. The build uses Apple's Game Controller connection notifications, extended-gamepad profiles, controller symbol names, directional hold-repeat, and face-button mappings. Device-specific behavior remains unverified.

Steam/Epic/Heroic uninstall handoffs require an installed authenticated client. Native Trash/cancellation/cache cleanup was exercised end-to-end; client-managed uninstalls were not. Epic pages may return HTTP 403. Genshin/other publisher pages may expose no artwork; bundled descriptions and cached application icons remain available. Alternate backdrops fall back to covers where no separate image exists. No new macOS compatibility is implied for VALORANT, Genshin Impact, or another Windows-only game.

## Earlier native launch baseline — version 0.1.0

The original native launcher passed 47 assertions including live provider checks. Loop Hero was launched from the app into its rendered main menu on this Mac; Mindustry's process/window and launch callback were observed. Test games were closed without entering gameplay or selecting saves. The native launch path remains in use in 0.2.0, with the Return shortcut additionally exercised through the isolated fixture above.
