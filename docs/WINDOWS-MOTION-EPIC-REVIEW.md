# Windows motion and Epic metadata review

## Changes

- Ported the SwiftUI carousel's spring response (0.42 seconds), damping (0.92), horizontal spacing, scale, opacity, and vertical positions to the shared desktop frontend. Input changes the current spring target without queuing prior navigation. Nine slots follow the animated position so rapid navigation does not remove cards that are still visible.
- Added Epic public product metadata with exact normalized title and installed namespace checks. Explicit product pages select their requested page; automatic matching selects `home`, never the first DLC page. Unavailable products continue through the existing Steam fallback.
- Preserved Epic namespace/catalog IDs during discovery and rescans, including existing libraries. Heroic's local Legendary catalog supplies metadata without account tokens. Portrait and landscape artwork have independent cache paths, and provider refresh retains custom edits and launch identity.
- Fixed asynchronous background loading: only the latest decoded request may replace the background, clearing selection invalidates pending work, and a failed decode can be retried. Images decode away from visible layers.
- Avoided rewriting the screen-reader announcement on every animation frame.

## Validation on Windows

- Frontend unit tests and production Vite build.
- Rust backend tests with the repository's locked dependencies, using the portable GNU Windows toolchain. The existing performance and live packaged-title tests remain opt-in.
- Explicit live Epic smoke test: Hades, Control, and Fortnite return descriptions, developers, and portraits; manual Hades product URL also succeeds.
- Windows debug executable builds successfully. Interactive app capture could not obtain a usable window in this execution environment. No claim is made about measured frame pacing, GPU performance, controller feel, or native Mac runtime behavior.
- Tests cover spring interruption/reversal, 60/120 Hz agreement, dropped frames, live reduced-motion changes, background decode races/retries, mismatched Epic identities, ambiguous/missing pages, separate artwork roles, custom metadata preservation, cache serialization, and existing-library discovery updates.

## Follow-up improvements

1. **Measure frame pacing on real libraries.** Record rapid keyboard/controller navigation with large covers on Windows WebView2 and the native Mac app. Compare median and tail frame times; use those results before making smoothness or GPU performance claims.
2. **Broaden Epic product resolution.** The public CMS does not expose every store product and title-derived slugs are not universal. Add verified namespace-to-product mappings or another supported official endpoint without reading launcher credentials. Keep manual product URLs and conservative Steam fallback available.
3. **Track missing fields per provider.** The current metadata retry policy treats incomplete entries uniformly. Recording field availability and provider outcomes would avoid repeated queries for fields that a provider never publishes while still retrying temporary failures.
4. **Add interactive Windows smoke coverage.** Existing CI builds each platform and runs unit tests. A WebView2 UI job with isolated libraries could check key navigation, selection announcements, and artwork replacement in the running app. Visual comparison with native SwiftUI still requires Mac review.

## Manual review after merging

- On Windows, browse rapidly in both directions, reverse while moving, resize, search/filter, and change the OS reduced-motion preference. Verify no queued movement or missing visible cards.
- Rescan an Epic/Heroic installation, refresh metadata, restart offline, and verify portrait, landscape, and custom overrides remain independent.
- On Mac, run the existing Swift validation and inspect the shared desktop edition. Native Swift sources are unchanged.
