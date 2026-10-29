#!/bin/bash
set -euo pipefail
MACOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MACOS_ROOT"
swift build -c release --product Joynite
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$MACOS_ROOT/dist/Joynite.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$MACOS_ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
cp "$BIN_DIR/Joynite" "$APP/Contents/MacOS/Joynite"
cp "$MACOS_ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$MACOS_ROOT/../LICENSE.md" "$APP/Contents/Resources/LICENSE.md"
cp "$MACOS_ROOT/../branding/mark-128.png" "$APP/Contents/Resources/BrandMark.png"
cp "$MACOS_ROOT/../branding/kofi.png" "$APP/Contents/Resources/Kofi.png"
ICONSET="$MACOS_ROOT/dist/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MACOS_ROOT/../branding/app-icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MACOS_ROOT/../branding/app-icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ditto -c -k --sequesterRsrc --keepParent "$APP" "$MACOS_ROOT/dist/Joynite-$VERSION-$(uname -m).zip"
python3 "$MACOS_ROOT/../scripts/sign-native-update.py" "$MACOS_ROOT/dist/Joynite-$VERSION-$(uname -m).zip" --tools "$MACOS_ROOT/.build/artifacts/sparkle/Sparkle/bin" --version "$VERSION"
printf 'Built: %s\n' "$APP"
if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    ditto "$APP" "$HOME/Applications/Joynite.app"
    printf 'Installed: %s\n' "$HOME/Applications/Joynite.app"
fi
