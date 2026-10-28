First native macOS preview of this Playnite fork, built for Apple Silicon and tested on macOS Tahoe.

- Native SwiftUI library with search, favorites, recent launch requests, and application icons/covers.
- Installed-game discovery for Steam libraries, Epic manifests, Heroic Epic/GOG manifests, Mac game folders, and Wine-wrapped applications.
- Mac application launching plus Steam/Epic/Heroic client launch URLs.
- Automatic Steam metadata matching. GOG catalog fallback and GOG/itch.io/Epic store-page metadata support. Ambiguous matches require selection.
- Local JSON library, atomic saves, previous-save backups, and import/export.
- Reproducible build script and CI workflow.

Validation: 47 assertions passed, including live Steam/GOG/itch.io requests. Loop Hero launched from the app into its rendered main menu on the development Mac. See macos/VALIDATION.md for tested and untested paths.

Download and unzip the arm64 archive, then move Playnite for Mac.app to Applications. This preview is ad-hoc signed, not Apple notarized; downloaded copies may require Open Anyway in macOS Privacy & Security.

This is an independent native implementation within the fork. It is not full feature parity with Windows Playnite. It imports installed games, not entire online account libraries, and does not run Windows Playnite plugins or supply a Windows compatibility runtime. Store clients and any required game runtime must already be installed. Epic may block store-page requests; equivalent Steam metadata can be selected instead.
