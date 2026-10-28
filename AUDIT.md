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
| macOS's default focus ring was blue | Keyboard focus conflicted with the orange theme | Keep a visible custom orange indicator and disable the system effect on toolbar controls |

## Measurement conditions

The earlier native 0.2 application was sampled on the user's Apple Silicon Mac: approximately 2 MB app-bundle disk usage and 22,912 KiB resident at an idle sample, CPU 0.0% in that sample. These are observations, not maximum-memory guarantees.

The shared frontend production build is approximately 31 KB before compression (HTML + JS + CSS), with no component framework. Navigation logic tests cover 20,000 positions, wrapping in both directions and stable neighboring identities. Those tests measure logical correctness, not GPU frame rate.

The native decoder cache is capped at 32 MB of estimated decoded pixel cost, with a 24-entry limit. Actual process memory includes SwiftUI, AppKit, GPU surfaces, and OS caching. The shared edition uses OS WebView2/WebKit/WebKitGTK and bounded card DOM rather than embedding Chromium. Linux AppImages may be larger because of packaged system dependencies.

A fair performance comparison with upstream Windows Playnite requires the same OS/hardware, library, artwork, plugins, and workload. This repository does not equate installer size, a single RSS sample, or a synthetic navigation test with that benchmark.

## Remaining validation limits

Physical controller hardware and authenticated Windows/Wine/CrossOver/Sikarugir clients require device/client testing. Prefix discovery and launch arguments can be validated with fixtures; game runtime compatibility and anti-cheat behavior cannot be inferred from those fixtures. Windows/Linux compilation and installer production are verified separately from actual game launches. The shared desktop UI is intentionally independent of the Windows WPF plugin and theme system.
