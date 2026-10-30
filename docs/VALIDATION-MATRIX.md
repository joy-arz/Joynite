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

- Version 0.7 shared macOS CI package: a copied offline library displayed favorite Inscryption in the center, with ranks 4/2/1/3/5 across the five cards after restart. The Mac locked during the remaining shared keyboard check; that check was not completed.
- Version 0.7 automated validation: 268 native assertions without live-provider checks, 22 Rust tests, 16 frontend tests, and 3 update-feed tests. Native macOS and shared Windows/Linux/macOS CI packages built successfully from commit 3a1debb5.

## Version 0.7.1 Windows recovery

Supplied screenshots show error 740 for Clair Obscur and error 5 for VALORANT in 0.7.0. Live official-provider validation finds Clair Obscur from `Expedition33-Win64-Shipping` and VALORANT from `VALORANT-Win64-Shipping`. Fixtures cover unique subtitle matching, ambiguity rejection, preserved custom overrides/launch counts, and registered/neighboring Riot Client routing. Windows CI exercises Unicode/null validation and a rejected missing-executable shell launch. Real game/UAC/Vanguard behavior requires retesting on the affected Windows device.

Local 0.7.1 validation: 27 shared Rust tests passed (two opt-in tests excluded); the separate live-provider test passed. The frontend's 16 tests and all three release-feed tests passed. A separate MSVC-target compile check validated the Windows API module and its test code. Windows CI completed its backend tests and installer build.

An isolated browser preview rendered the actual shared frontend with copied artwork and mocked local IPC. At 1280×720, the displayed background image bounds were exactly (0,0)–(1280,720), with object-fit: cover. Space → inkriotion → Enter selected Inscryption; Tab + Right returned to carousel navigation. This checks the web UI, not Windows WebView/UAC or a real game launch. Preview files and server were removed afterward.

## Version 0.8 upstream adaptation

Local validation: 35 shared Rust tests passed, plus the separately run live official-provider test. The frontend's 16 tests, three release-feed tests, catalog sync and version alignment passed. New fixtures cover GOG registry/manifests, primary arguments/working folders, Linux desktop sections and hidden user overrides, Windows quote round trips, metadata field fallback/custom precedence, and launch settings persistence/save failure. Windows CI additionally compares argument encoding with CommandLineToArgvW. A separate MSVC-target compile check covers the shell API module.

The actual shared launch editor was checked in an isolated browser preview with copied artwork and mocked IPC. Application path, multiword arguments, working directory and per-game elevation persisted across reopening the form; restoring Automatic removed the override. No real game launched or real library changed. Preview files and server were removed. Real Windows consent/GOG/Galaxy, Linux desktop/Flatpak and physical-controller runs remain separate device tests.
