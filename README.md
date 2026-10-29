# <img src="branding/preview.png" width="48" alt="Joynite icon"> Joynite

Your games. One smooth carousel.

Joynite is a redesigned, lightweight game library and launcher with a black-and-orange interface, persistent offline metadata, custom artwork, and keyboard/controller navigation. Choose the native SwiftUI edition for macOS or the Rust/system-webview edition for Windows, Linux, and macOS.

Joynite retains Playnite's original source and license, but the shipped SwiftUI and Rust/webview apps are separate implementations. They do not load Playnite's .NET addons or WPF themes. [Upstream comparison and adapted behavior](docs/UPSTREAM-COMPARISON.md).

**[Download Joynite](https://github.com/joy-arz/Joynite/releases)** · **[macOS guide](macos/README.md)** · **[Windows/Linux guide](desktop/README.md)** · **[Support on Ko-fi](https://ko-fi.com/joyarz)**

## Your library, front and center

![Joynite carousel with Inscryption selected in the center](docs/screenshots/joynite-carousel.png)

Five cards wrap continuously. The selected game is largest and centered, with its title and description inside the card. Interruptible sliding follows rapid input. Portrait covers and inspection images fit completely over a matching softened fill. Alternate backgrounds cover the full application viewport.

![Joynite showing Inscryption artwork and saved metadata](docs/screenshots/joynite-inscryption-details.png)

## Features

- **Offline first.** Descriptions, developers, genres, dates, favorites, and artwork remain on disk across restarts. Custom text and three independent image overrides survive automatic refresh.
- **Per-game launch settings (shared edition).** Keep automatic store/Wine routing or configure an application, arguments, working directory or supported client URL. Windows can request administrator permission for that game only. Native GOG primary tasks and Linux XDG/Flatpak game entries are discovered.
- **Automatic metadata.** Steam, GOG, itch.io, Epic/store-page matching, and bundled publisher metadata for Roblox, VALORANT, Genshin Impact, EDOPro, YGOPro/Percy, YGOPro 2, KoishiPro, YGO Omega, MDPro3, and more. Provider availability varies.
- **Installed-game discovery.** Steam, Epic/Heroic manifests, native game applications, and Steam inside Wine, CrossOver, and Sikarugir/Wineskin prefixes. Each compatibility installation keeps its original runtime and prefix.
- **Your most-opened games first.** Startup puts the top five around the center: 4th · 2nd · 1st · 3rd · 5th. Favorites rank first, then successful launches made through Joynite. Remaining games continue in the same ranking; alphabetical ties stay stable. Counts are local and start at zero for older libraries.
- **Fast search.** Space expands search into the center. Enter selects a case-insensitive, typo-tolerant match and returns to browsing. Up/Down chooses a suggestion; direct matches suppress weak fuzzy alternatives. Tab cannot trap the library in search.
- **Portable backups.** Export metadata and available cached/custom artwork as a ZIP; restore verifies the manifest and hashes and keeps existing game edits. Backups have progress and cancellation; an optional preview verifies the archive without changing the library.
- **Direct controls.** Arrow keys or A/D browse. Enter/Return launches immediately. Shift toggles details; L toggles libraries. Both sidebars start hidden. Hints follow the active keyboard or controller.
- **Quiet updates.** Official GitHub releases are checked in the background. A small top-right notice offers Update now, Update later, or skipping that version. Downloads begin only on request and signatures are verified before installation.
- **Launch at login.** An optional setting opens Joynite when you sign in on Windows, Linux, or macOS. It is off by default.
- **Safer uninstall.** Confirmed native application removal uses Trash. Steam and other stores use their original uninstall flow; metadata remains until removal is confirmed. Disconnected disks do not trigger cleanup.
- **Small implementation.** Native SwiftUI or Rust plus the system webview; no bundled browser or Node runtime. [Measurements and validation limits](AUDIT.md) describe what has actually been checked.

## Settings

![Joynite startup setting](docs/screenshots/joynite-settings.png)

Open **Settings** in the app. On macOS, use **Joynite → Settings…** or Command-comma. The shared desktop edition also has a footer Settings button and Command/Ctrl-comma. Enable **Launch Joynite when I sign in** to opt in; disable it to remove the startup registration. A desktop session must be signed in before the app can open.

Existing libraries from this fork’s previous Playnite-branded releases are copied into the Joynite data directory on first launch. Metadata, cached images, favorites, custom overrides, and history stay intact. Original data remains available as a recovery copy. The native and shared Mac editions keep separate library directories.

## Software updates

Update checks do not block library scanning or navigation. Offline launches stay quiet. **Update later** snoozes that release for 24 hours; **Don’t remind me again** skips it until a newer version is released. Use **Check for updates…** in Settings to check manually. Updates preserve the library and game installations.

Version 0.4 users install 0.5 once manually to enable future in-app updates. See [signed update delivery](updates/README.md) and the [post-update review](IMPROVEMENTS.md).

## Build

Native macOS:

```sh
swift run --package-path macos JoyniteValidation
macos/scripts/build-app.sh --install
```

Shared desktop, after installing the [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/):

```sh
cd desktop
npm ci
npm test
npm run tauri -- build
```

See the platform guides for compatibility limits. Discovery and metadata do not make a Windows-only game or its anti-cheat work on another operating system. Mac builds are ad-hoc signed rather than notarized. Original Windows Playnite plugins and themes are not portable to these interfaces.

## Support Joynite

[<img src="branding/kofi.svg" width="26" alt="Ko-fi cup"> **Support joy-arz on Ko-fi**](https://ko-fi.com/joyarz)

If Joynite makes your library easier to use, you can support its development. The same orange Ko-fi cup is available in the app’s bottom-right corner.

## Contributor

**[joy-arz](https://github.com/joy-arz)** — Joynite maintainer and contributor.

Joynite builds on [Playnite](https://github.com/JosefNemec/Playnite) by Josef Nemec and its original contributors. Their source history and MIT license notices remain intact. The original project’s README is preserved in [docs/UPSTREAM-README.md](docs/UPSTREAM-README.md).
