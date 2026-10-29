# Joynite 0.6 validation matrix

Observed on this Apple Silicon Mac on 2026-10-29. No real game was uninstalled.

| Area | Evidence | Limit |
| --- | --- | --- |
| Native keyboard | Tab then Right moved the carousel; Space focused a centered search; inkriotion and INSCRYPTION selected Inscryption; Enter closed search; a later arrow moved normally. | UI automation verifies end states; it does not provide an animation frame-time trace. |
| Shared keyboard | Isolated shared app: inkriotion suggested Inscryption; Enter returned to the header; Tab + Right selected the next game. Visual inspection caught and corrected the search dimming stack. | Checked on macOS system webview; Windows/Linux package builds are separate. |
| Native game launch | Mindustry launched through Joynite. Its actual Play/Settings/Quit main menu was visually observed; the game was then closed. | One installed native game/client version. |
| Sikarugir wrapper | The Binding of Isaac Rebirth launched through Joynite; its own Sikarugir, wineserver and isaac-ng.exe processes started. | The game window was not available through the UI automation surface. Main-menu arrival remains unverified. Only the processes started for this test were stopped. |
| Wine/CrossOver/Sikarugir Steam | Prefix-specific discovery and argument/environment fixtures pass. | Real Steam clients across these runtimes are not all installed/verified here. |
| Controller | Keyboard/controller hint and routing fixtures retained. | No physical-controller matrix completed. |
| Updates | 0.5 published packages passed signature checks; altered bytes were rejected. 0.6 IPC tests cover interrupted checks and failed installation without relaunch. | Actual Windows/Linux install/restart, full-disk and native interrupted-replacement exercises remain unperformed. |
| Backups | Native/Rust round trips preserve metadata/artwork and existing edits; truncated data, path escapes and changed content are rejected. | This backs up Joynite's library/cache, not game binaries or game save files. |
| macOS signing | Ad-hoc app and signed update archives. Local identity inventory reports zero valid code-signing identities. | Developer ID/notarization needs the maintainer's Apple signing setup. |

Reproduce scale profiles with `swift run --package-path macos -c release JoyniteValidation --benchmark` and `cargo test --release --manifest-path desktop/src-tauri/Cargo.toml large_library_profile -- --ignored --nocapture`. Fixture timings do not establish full-library artwork, slow-disk or other-device performance.

## Version 0.7 follow-up

- A copied seven-game native library verified favorite-first startup and the 4/2/1/3/5 visible arrangement. Removing its favorite and reopening selected the highest-count game. The freshly played game did not outrank a higher counter merely because lastPlayed was newer.
- The native search test submitted uppercase Mindustry rapidly, closed search synchronously and launched with the next Enter. The isolated count changed 60 → 61; the real library's field remained absent. The test game was closed afterward. Up/Down selection and Tab/arrow browsing were also checked.
- Core tests cover canceled export/restore, unchanged existing backups, optional preview without library writes, failed counter persistence, sparse metadata events and local launch reports. Real platform/device constraints above remain.
