# macOS validation record

Date: 2026-10-28. Environment: Apple Silicon Mac, macOS Tahoe (Darwin 25.6.0), Swift 6.3.1, Command Line Tools SDK 26.4. Deployment target: macOS 14.

## Automated validation

Command: `swift run --package-path macos PlayniteValidation --live`

Result: **47 assertions, 0 failures.**

```
PASS: VDF nested objects, escaped paths, malformed input
PASS: Steam installed-state bitmask and directory checks
PASS: Atomic persistence, backup, corrupt library handling
PASS: Steam metadata preserves launch identity
PASS: Store HTML, entities, relative artwork, host validation
PASS: Epic launch identity, URL escaping, incomplete installs
PASS: Mac application names, missing paths, self-exclusion
PASS: Conservative title normalization
PASS: live Steam search and app details
PASS: live itch.io metadata
PASS: live GOG metadata
47 assertions. 0 failures.
```

Live Steam search returned the exact Hades app ID 1145360; details supplied the title, description, and artwork. itch.io Stacklands and GOG Loop Hero pages supplied non-empty descriptions and artwork. Public store responses may change independently of this release.

## Native application checks

- Built an optimized Apple Silicon executable and `.app` bundle using `scripts/build-app.sh --install`.
- Installed into `~/Applications/Playnite for Mac.app` and opened the native window.
- Initial scan discovered five installed games. Four received automatic metadata from exact Steam matches. One unmatched game remained available with its local icon and a notice; no incorrect metadata was assigned.
- Detected the locally installed Sikarugir game wrapper through its Wine prefix. No runtime configuration was changed.
- Selected Mindustry and pressed **Play**. Observed the game process and registered window. The library recorded the successful launch callback. No gameplay was exercised.
- Selected Loop Hero and pressed **Play**. Observed its rendered **LOOP HERO 1.155 (mac)** main menu. The library recorded the successful launch callback.
- Closed both game test launches without entering gameplay. No save slots were opened.
- Reviewed the native library layout. Corrected Play-button contrast for inactive windows and aligned card artwork to the top of each grid row.

## Limits of this record

Steam/Epic/Heroic client launch handoffs were validated structurally, not against installed, authenticated clients on this Mac. Steam's local installation parser was exercised with controlled manifests, including combined installation-state flags. Heroic and Epic import formats need field validation on real client installations. The Sikarugir wrapper was discovered but was not launched during these checks. Intel hardware, online account-library synchronization, game installation, cloud saves, and Windows Playnite extensions are outside this release's validation.

Epic's public store page returned HTTP 403 from this network. This condition produces a metadata error with a Steam-match fallback in the interface; successful Epic page retrieval is not claimed. SteamDB is not used as an automated data source.
