# Implementation audit and performance record

## 0.3 feature pass and immediate improvements

The review covered carousel rendering, image decoding, stored library data, process launching, compatibility-prefix routing, and portability. Findings were turned into changes in the same development pass.

| Finding | Impact | Implemented change |
| --- | --- | --- |
| Images were reopened from disk while SwiftUI recomputed card bodies | Navigation could repeatedly load/decode the same artwork | Decode off the UI thread and reuse a bounded 32 MB image cache |
| Wrapped game IDs were also view identities | Very fast movement and wrap-around could send a reused card across the carousel | Use continuous positional identities, with interruptible motion and a bounded visible neighborhood |
| Large shadows, perspective transforms, and live backdrop blur | Extra raster/compositor work on rapid changes | Use simpler 2D movement/scaling, smaller static shadows, and debounced backdrop changes |
| Portrait covers were reused in the details panel | Wrong aspect ratio or cropping | Independent portrait, landscape, and background keys; candidate dimension checks and fitted covers |
| Startup scanning only ran for an empty native library | Newly installed games required a manual scan | Detect installations on every process startup; retain manual scan commands |
| A generic Steam URL could select native Steam for a Wine game | Wrong client/prefix and failed game launch | Keep runtime, prefix, Steam executable, working directory, and launch arguments per installation |
| Sikarugir launcher forwarding is not a reliable generic CLI contract | Arguments after the executable may be ignored | Detect wrapper prefixes and use their bundled Wine plan, without editing wrapper settings |
| Read-only library guards happened after some in-memory edits | Failed saves could still change the current view | Guard mutation/uninstall paths before editing records |
| Background responses could arrive out of order | A stale response could replace a newer UI snapshot | Monotonic library revisions; reject stale frontend snapshots and stale metadata updates |
| Dropped process handles were not explicitly reaped in the shared backend | Repeated launches could leave exited child processes behind | Reap spawned children on waiting threads without blocking the UI |
| Drag release could also trigger a card click | A completed swipe could select a card again or undo the movement | Suppress the synthetic click following a drag |
| Existing artwork was saved again on every hydration pass | Redundant JSON and backup writes | Save image-key changes only; preserve unchanged records |
| Image keys came from imported JSON | Malformed Unicode keys could make unsafe string slicing fail | Validate ASCII key bytes and constrain asset access to the managed cache |
| Very short animations and cards removed at the edge | Quick navigation felt abrupt despite lower CPU cost | Retain nine positional cards, five visible; use longer interruptible 0.42 s native springs / 380 ms compositor transitions; remove forced synchronous layout from card creation |
| Wide Roblox/publisher art did not match portrait frames | Cropping cut off artwork or plain letterboxing left gaps | Fit the complete sharp foreground and fill remaining space using a separately cached low-resolution softened copy |
| Small custom uploads were enlarged to cache maxima | Wasted pixels, storage, and decoding | Downscale only; retain smaller image dimensions |
| Provider refresh shared storage with manual edits | Custom fields could be overwritten | Store per-field overrides separately from the latest automatic baseline; independent local image overrides and reset controls |
| Imported image dimensions were checked too late in the native cache | Oversized images could allocate before rejection | Validate dimensions and pixel count before ImageIO thumbnail decoding |
| macOS's default focus ring was blue | Keyboard focus conflicted with the orange theme | Keep a visible custom orange indicator and disable the system effect on toolbar controls |

## Measurement conditions

The earlier native 0.2 application was sampled on the user's Apple Silicon Mac: approximately 2 MB app-bundle disk usage and 22,912 KiB resident at an idle sample, CPU 0.0% in that sample. These are observations, not maximum-memory guarantees.

The shared frontend production build is approximately 43 KB before compression (HTML + JS + CSS + SVG logo), about 16 KB gzip, with no component framework. Navigation logic tests cover 20,000 positions, wrapping in both directions and stable neighboring identities. Those tests measure logical correctness, not GPU frame rate.

The native decoder cache is capped at 32 MB of estimated decoded pixel cost, with a 24-entry limit. Actual process memory includes SwiftUI, AppKit, GPU surfaces, and OS caching. The shared edition uses OS WebView2/WebKit/WebKitGTK and bounded card DOM rather than embedding Chromium. Linux AppImages may be larger because of packaged system dependencies.

A fair performance comparison with upstream Windows Playnite requires the same OS/hardware, library, artwork, plugins, and workload. This repository does not equate installer size, a single RSS sample, or a synthetic navigation test with that benchmark.

Native 0.3 local bundle: 2,784 KiB allocated disk usage; shared macOS 0.3 bundle: 6,348 KiB. A native 0.3 process with six cached games and repeated navigation was sampled at 44,528 KiB RSS and 0.0% CPU after settling. This includes the new retained cards and fitted/softened artwork and is not a peak measurement.

## Remaining validation limits

Physical controller hardware and authenticated Windows/Wine/CrossOver/Sikarugir clients require device/client testing. Prefix discovery and launch arguments can be validated with fixtures; game runtime compatibility and anti-cheat behavior cannot be inferred from those fixtures. Windows/Linux compilation and installer production are verified separately from actual game launches. The shared desktop UI is intentionally independent of the Windows WPF plugin and theme system.

## Version 0.3 validation

Native core: 136 live assertions and 126 explicitly offline assertions, all passing. Shared backend: 13 tests, all passing. Navigation/input model: 5 tests, including 20,000 positions and stable identities for nine buffered nodes, all passing. Custom text survives provider refresh and serialization, reset restores the latest automatic values, and imported images survive removal of their source file. A 120×40 image stays 120×40 rather than being enlarged to 1600 pixels. Soft fills are cached at no more than 64 pixels per dimension.

UI checks use disposable offline copies of the six-game native library. They do not uninstall or alter real games. FPS is not inferred from passing unit tests; smoothness remains subject to the host compositor and display workload. Physical controller and authenticated compatibility-client testing remain outstanding hardware/client checks.
