# Application mark

The mark preserves the path geometry supplied in Logo.svg. It uses a transparent yellow-to-orange gradient (#FFE35B, #FFD12B, #FF9708, #D94D00). The app icon adds a #101010 rounded background and a subtle brown border to keep bright edges distinct. This palette remains separate from the orange focus/action color in the interface.

logo.svg and app-icon.svg are the vector sources. Run `npm run brand --prefix desktop` to render PNG assets and copy the header SVG. mark-128.png avoids decoding the 1024-pixel source for a small native header. Application icon variants are generated with Tauri’s icon command; the native build script generates its ICNS from app-icon.png.
