## Playnite for Mac 0.2.0

A black-and-orange, controller-ready carousel with persistent offline metadata.

- Five large cards wrap continuously. The selected game is centered and enlarged; titles and descriptions live inside the cards.
- Steam portrait covers are preferred, with cached banners/icons as fallback. A separate screenshot becomes the backdrop where available.
- Both sidebars start hidden. Left/Right or A/D browse, Return launches directly, Shift toggles game details, L toggles libraries, F toggles favorites, and Escape closes panels. Search fields retain normal text editing.
- Connected extended controllers use D-pad/left stick and shoulders to browse, bottom face button to launch, top face button for details, left face button for libraries, and right face button to close panels. On-screen hints use controller-provided glyphs and follow the active input.
- Metadata text, covers, and backgrounds persist on disk. Already cached images need no network access. Hide retains metadata; Restore hidden games brings entries back.
- Native uninstall moves the selected application bundle to Trash after confirmation, including any data inside the bundle. Metadata/cache cleanup happens after success. Steam opens its uninstall dialog. Epic and Heroic open the client for its own uninstall command; cleanup waits for confirmed removal. Disconnected disks do not count as uninstall.
- Publisher catalog adds Roblox, VALORANT, Genshin Impact, Honkai: Star Rail, Zenless Zone Zero, League of Legends, and Minecraft. Descriptions are bundled; publisher artwork is cached when available. Metadata does not imply macOS compatibility.

Existing 0.1 libraries migrate without losing metadata, favorites, or launch history. The app remains an independent native implementation in this fork, with no Windows plugin compatibility or built-in Windows runtime. Epic store pages may block automated access. This Apple Silicon preview is ad-hoc signed, not Apple notarized.
