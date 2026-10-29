# Playnite comparison and the Joynite 0.8 adaptation

Reviewed on 2026-10-30. This is a comparison of implementation behavior, not a claim of plugin or feature parity.

## Which code actually runs

This repository is a Git fork and retains the original `source/` tree and MIT license. The retained source matches upstream master at `3e8abb241873e326e27c75b59dd0d2ea367698e3` (`git diff upstream/master -- source` is empty). However, released Joynite packages are built from `macos/` (native SwiftUI) and `desktop/` (Rust/Tauri plus a system webview). They do not run the original C# WPF app or load its .NET plugins/themes. That distinction is now stated in the main README.

[Official Playnite](https://github.com/JosefNemec/Playnite/blob/3e8abb241873e326e27c75b59dd0d2ea367698e3/README.md) requires Windows 10 or 11. Its desktop project targets .NET Framework 4.6.2. There is no official Linux launch/discovery implementation in that source to copy. Linux behavior here follows the freedesktop desktop-entry standard and delegates Exec, Path, terminal and D-Bus activation to GIO.

## Source-to-change mapping

| Inspected official implementation | Pattern | Joynite 0.8 shared edition |
| --- | --- | --- |
| [GameAction](https://github.com/JosefNemec/Playnite/blob/3e8abb241873e326e27c75b59dd0d2ea367698e3/source/PlayniteSDK/Models/GameAction.cs) and [GenericGameController](https://github.com/JosefNemec/Playnite/blob/3e8abb241873e326e27c75b59dd0d2ea367698e3/source/Playnite/Controllers/GenericGameController.cs) | Keep action type, executable/URL, arguments and working directory independently of metadata. | Per-game Launch settings. Automatic retains the discovered client/Wine route; explicit file or supported client-URL overrides are separate, optional and reversible. |
| [ProcessStarter](https://github.com/JosefNemec/Playnite/blob/3e8abb241873e326e27c75b59dd0d2ea367698e3/source/Playnite/Common/ProcessStarter.cs) | Default working directory to the executable folder; support explicit elevation. | Windows shell launches retain shortcut behavior. A per-game administrator option requests normal Windows consent; the Joynite process stays unelevated. Argument arrays are quoted using Windows argument rules; Linux arguments are passed directly as an array. |
| [GogLibrary](https://github.com/JosefNemec/PlayniteExtensions/blob/886468f65724e6fd104f3a09847a17ba57cfb430/source/Libraries/GogLibrary/GogLibrary.cs) and [GogGameTaskInfo](https://github.com/JosefNemec/PlayniteExtensions/blob/886468f65724e6fd104f3a09847a17ba57cfb430/source/Libraries/GogLibrary/Models/GogGameTaskInfo.cs) | Discover installed GOG games through uninstall entries; use primary `goggame-*.info` play tasks and working directories. | Windows scans GOG uninstall entries and configured GOG folders, reads one unambiguous primary executable task, preserves arguments, and resolves targets relative to the installation or task working folder. Discovery-owned defaults stay separate from user overrides. |
| [MetadataDownloader.ProcessField](https://github.com/JosefNemec/Playnite/blob/3e8abb241873e326e27c75b59dd0d2ea367698e3/source/Playnite/Metadata/MetadataDownloader.cs) | Try ordered providers per field rather than accepting one incomplete record. | Store/publisher data has priority. A uniquely matched Steam record fills missing fields and can provide portrait art, without replacing the installed store ID, client route or custom overrides. Incomplete records retry after a 24-hour cooldown. |
| [freedesktop Exec specification](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html) | Preserve quoting, field codes, working directory and desktop activation. | Parse only the Desktop Entry section for inventory, require the exact Game category, respect hidden/no-display entries and user precedence, include XDG/Flatpak export locations, and let GIO perform activation. A rejected GIO request is reported as failure instead of counted as an accepted launch. |

The official extensions snapshot was archived on GitHub and its README points to Codeberg. The pinned GitHub snapshot above is the exact source inspected; this review does not claim to have audited all later Codeberg changes.

## Deliberate differences and remaining limits

- Launch counts still come only from accepted requests made through Joynite. Playnite's imported store playtime, account history and directory-wide process monitoring do not seed these counters.
- Launch settings are in the shared Windows/Linux/macOS edition. The separate native SwiftUI edition is version-aligned and keeps its existing launch interface.
- This does not add .NET addon/theme compatibility, arbitrary startup scripts, all emulator profiles, account authentication, uninstalled cloud libraries or every GOG alternate play task. Ambiguous/unresolved GOG tasks produce a notice and can be configured using a working shortcut or explicit action.
- Native Linux executables, AppImages and desktop entries can be selected explicitly. A Windows executable still needs a suitable existing compatibility runtime on Linux; a metadata match does not establish runtime/anti-cheat compatibility.
- Real GOG/Galaxy installations, Windows consent dialogs, Linux desktop/Flatpak sessions and physical controllers require device tests. Fixtures and CI establish parsing, persistence, argument handling and build behavior, not game-menu arrival.
