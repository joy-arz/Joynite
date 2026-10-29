# Joynite review after the 0.5 update implementation

## Findings addressed in this release

| Priority | Finding | Change and evidence |
| --- | --- | --- |
| High | The app had no trusted in-app update path. Downloading a release without validating its origin/signature would create an installer integrity gap. | Native macOS uses Sparkle 2.10.1; shared desktop uses Tauri updater 2.14.1. Public verification keys are bundled, private signing keys stay outside the repository and in encrypted release secrets. Native archives are signed and verified during packaging. |
| High | A skipped or postponed update could otherwise reappear on every launch. | Per-version reminder persistence, a 24-hour Later delay, and exact-version skipping. A newer release bypasses the old preference. Manual checks remain available. Unit and DOM tests cover restart serialization and newer-version behavior. |
| High | Native custom metadata could report success after the library write failed. | Game edits are saved before publishing the changed in-memory library. The custom editor now propagates save errors rather than dismissing with a success message. A blocked-destination test verifies the failure path. |
| Medium | Carousel keyboard handlers could consume Escape/arrows while a macOS menu was tracking. | Input pauses during menu tracking and while a menu-bar item is highlighted. Controller repeats also stop when a menu opens. |
| Medium | Focused action buttons could compete with the global Enter-to-play shortcut. | Native update controls pause library shortcuts while focused. Shared non-card action buttons keep normal Enter/Space behavior. |
| Medium | Release version fields or native/shared artifacts could drift apart. | A version-consistency check covers Info.plist/build version, Cargo, npm and Tauri config. Release publishing accepts successful main-branch push builds from the same commit only, and feed generation rejects missing signatures, mixed versions and incomplete package sets. |
| Medium | Background update failures could become startup interruptions. | A deferred, bounded check runs independently of game discovery. Known offline state skips the request. Connection errors stay out of modal alerts and out of the game-library status/error list. |

## Follow-up implementation in 0.6.0

| Priority | Result |
| --- | --- |
| Portable backups | Implemented in both editions. ZIP contains library.json, available game-cache/custom image files and a format-1 SHA-256 manifest. Restore validates the complete file set before applying it, rejects path traversal/symlinks/unexpected entries, enforces entry/archive limits and merges without replacing existing game edits. Legacy JSON import remains available. |
| Large-library search | Profiled 1,000 and 10,000 synthetic records. Native queries move off the main thread above 500 candidates; shared queries use a Web Worker above 500 records. Canceled/stale results cannot replace a newer query. Native title/genre indexes are reused for unchanged records. |
| Storage architecture | Retained atomic JSON after measurement rather than introducing an unmeasured database migration. Shared release-mode 10,000-record snapshot: 1.91 ms; serialization: 10.92 ms; save: 26.60 ms. Native initial 10,000-record index: 78.03 ms; synchronous fuzzy baseline: 81.75 ms; save: 70.71 ms. The native fuzzy timing includes query normalization and motivated moving search off the UI thread. These are synthetic measurements on this Mac, not guarantees for full image libraries or other hardware. |
| Update failure UX | Added interrupted-service and failed-install IPC tests. A failed check keeps the notice hidden; a failed install leaves the notice retryable and never requests relaunch. Archive tests reject truncated input and changed contents while retaining the existing library. Actual signed packages were verified and altered bytes rejected in 0.5 release validation. |
| Focus/navigation | Tab/Shift-Tab no longer transfer library focus; Space opens center search; Enter selects and collapses, Escape cancels. Native UI verified with inkriotion and INSCRYPTION, then Tab + arrow navigation. Dialog forms retain ordinary Tab traversal. |

## Remaining external validation and constraints

- **Apple notarization:** `security find-identity -v -p codesigning` reported zero valid identities on this host on 2026-10-29. Developer ID signing/notarization cannot be completed here without the maintainer's Apple signing identity and notarization credentials. The official Mac build remains ad-hoc signed; archive signature verification remains active.
- **Physical device matrix:** Native Mindustry was launched from Joynite and its real main menu was observed, then it was closed. Wine/CrossOver/Sikarugir prefix-routing fixtures pass; the installed Sikarugir wrapper is checked separately in the validation matrix. This does not establish all client versions, game/anti-cheat support or physical controller behavior. No physical-controller matrix has been completed.
- **Real installation recovery:** Interrupted service and failed-install UI behavior are covered with platform IPC mocks. Real disk-full, system authorization denial, Windows/Linux replacement/restart cycles and interrupted native Sparkle replacement still require dedicated devices or an isolated VM. No test deliberately fills or weakens the user's system disk.
- **Storage scale:** Atomic library writes and snapshots still cover the full library. Future profiling should add realistic summaries/artwork plus slow external disks before selecting incremental persistence or snapshot paging.

## Validation boundaries

Native core: 167 live assertions and 157 offline assertions. Shared core: 15 Rust tests. Frontend: 9 tests including the actual notification DOM with mocked platform IPC. Release feed generation: 3 tests. Update-notice UI uses an isolated offline library and an explicitly marked validation-only notification preview. Search UI was checked in the native installed library and in an isolated shared-library copy. No fabricated public release is published for a UI test. Signature verification during native packaging uses the actual archive; release feeds and signed artifacts are published together before an official release becomes latest.

Version 0.6 validation: 181 native assertions with live providers / 171 without live-provider checks; 17 Rust tests plus a separately run release-mode scale profile; 10 frontend tests including failure-path update IPC and typo ranking; 3 feed tests. Both native and shared UI checks confirmed search submission and resumed arrow navigation.
