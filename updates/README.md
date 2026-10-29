# Signed update delivery

Joynite checks quietly a few seconds after launch. Native macOS reads the latest official GitHub release, rejects drafts/prereleases/older versions and unsupported architecture assets, and uses Sparkle only after Update now. Shared desktop checks latest.json through the Tauri updater. Both use pinned public keys and HTTPS. Updates replace the application, not the library or games.

- Update later postpones that version for 24 hours. A newer release can appear immediately.
- Don’t remind me again skips only that version. Manual Check for updates can still reveal it.
- Offline launch does not display a check or error notification. Explicit JOYNITE_OFFLINE mode disables update requests too.
- Downloads start only after Update now. The OS can request installer authorization for a system-wide installation.

## Release procedure

1. Run `python3 scripts/set-release-version.py X.Y.Z` to update app version fields without changing dependency pins, then `python3 scripts/validate-release-config.py`.
2. Push to main and wait for native macOS plus shared Windows/Linux/macOS builds of the same commit to succeed.
3. Create an official-release draft for the version. Dispatch Publish desktop packages with the two successful run IDs and the draft tag.
4. The publisher downloads packages and signatures, validates provenance/version consistency, generates latest.json and appcast.xml, then uploads everything to the draft. Inspect the release asset set before publishing it as latest.

Private keys are backed up outside this repository under the maintainer’s `.joynite/signing` directory and stored in encrypted repository secrets `JOYNITE_SPARKLE_PRIVATE_KEY` / `JOYNITE_TAURI_PRIVATE_KEY`. `public-keys.json` contains verification keys only. Preserve private keys securely: replacing a verification key without a transition release prevents existing installations from accepting later updates. Never commit or include private keys in app bundles or release assets.

The shared Linux feed includes AppImage and DEB targets. Windows uses the NSIS installer. Shared macOS receives its signed application archive; native macOS receives the independently signed native ZIP. Mixing the two Mac editions is prevented by separate feeds/packages and native bundle validation.

Version 0.4 has no updater, so users install 0.5 once manually. Later updates can then be installed inside Joynite.
