# Joynite review after the 0.5 update implementation

## Findings addressed in this release

| Priority | Finding | Change and evidence |
| --- | --- | --- |
| High | The app had no trusted in-app update path. Downloading a release without validating its origin/signature would create an installer integrity gap. | Native macOS uses Sparkle 2.10.1; shared desktop uses Tauri updater 2.14.1. Public verification keys are bundled, private signing keys stay outside the repository and in encrypted release secrets. Native archives are signed and verified during packaging. |
| High | A skipped or postponed update could otherwise reappear on every launch. | Per-version reminder persistence, a 24-hour Later delay, and exact-version skipping. A newer release bypasses the old preference. Manual checks remain available. Unit and DOM tests cover restart serialization and newer-version behavior. |
| High | Native custom metadata could report success after the library write failed. | Game edits are saved before publishing the changed in-memory library. The custom editor now propagates save errors rather than dismissing with a success message. A blocked-destination test verifies the failure path. |
| Medium | Carousel keyboard handlers could consume Escape/arrows while a macOS menu was tracking. | Input pauses during menu tracking. Controller repeats also stop when a menu opens. |
| Medium | Focused action buttons could compete with the global Enter-to-play shortcut. | Native update controls pause library shortcuts while focused. Shared non-card action buttons keep normal Enter/Space behavior. |
| Medium | Release version fields or native/shared artifacts could drift apart. | A version-consistency check covers Info.plist/build version, Cargo, npm and Tauri config. Release publishing accepts successful main-branch push builds from the same commit only, and feed generation rejects missing signatures, mixed versions and incomplete package sets. |
| Medium | Background update failures could become startup interruptions. | A deferred, bounded check runs independently of game discovery. Known offline state skips the request. Connection errors stay out of modal alerts and out of the game-library status/error list. |

## Remaining improvement priorities

1. **Portable backups.** JSON export contains metadata and image keys but does not package cached/custom image files. A versioned ZIP export with a manifest and restore validation would make machine migration simpler. Existing data and its backup remain local; users can copy Media alongside the JSON today.
2. **Large-library profiling and storage.** Rendering retains a bounded card neighborhood, but metadata snapshots and library saves still serialize the full library. Benchmark 1,000 and 10,000 entries before choosing incremental storage or paged snapshots. The current six-game measurements do not establish performance at that scale.
3. **Runtime and device validation.** Prefix-specific launch plans are tested, but a launch request does not prove a game reached its main menu. Add real Wine/CrossOver/Sikarugir client tests and a physical-controller matrix. Keep store-managed uninstall delegated to the owning client.
4. **macOS distribution polish.** The Mac app remains ad-hoc signed, without Developer ID notarization. Signed update archives protect update integrity; they do not replace Apple notarization or remove every first-install OS warning.
5. **Update recovery exercises.** Extend testing to interrupted downloads, insufficient disk space, unwritable Applications folders, and real Windows/Linux installation/restart cycles. The standard updater frameworks provide their installation mechanisms; unit, DOM, packaging and signature checks do not substitute for those device tests.

## Validation boundaries

Native core: 167 live assertions and 157 offline assertions. Shared core: 15 Rust tests. Frontend: 9 tests including the actual notification DOM with mocked platform IPC. Release feed generation: 3 tests. Native UI uses an isolated offline library and an explicitly marked validation-only notification preview. No fabricated public release is published for a UI test. Signature verification during native packaging uses the actual archive; release feeds and signed artifacts are published together before an official release becomes latest.
