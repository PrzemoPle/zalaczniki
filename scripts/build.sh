#!/usr/bin/env bash
#
# Buduje Załączniki.app — plik universal (Intel + Apple Silicon), macOS 12.3+.
# Podpisuje certyfikatem Developer ID, jeśli jest w pęku kluczy.
#
#   ./scripts/build.sh              budowa + podpis
#   ./scripts/build.sh --notaryzuj  dodatkowo notaryzacja (profil notarytool „zalaczniki")
#
# Uwaga: narzędzia z macOS 27 nie mają już bibliotek zgodności Swift dla Intela,
# stąd -runtime-compatibility-version none i minimum 12.3 (tam runtime 5.6 jest w systemie).
set -euo pipefail

KORZEN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUDOWA="$KORZEN/build"
APP="$BUDOWA/Załączniki.app"
WERSJA="1.1.0"
DATA_WYDANIA="2026-09-30"   # pokazywana w oknie „O aplikacji"
MINIMUM="12.3"
PROFIL="${ZALACZNIKI_PROFIL_NOTARYZACJI:-zalaczniki}"

info() { printf '\033[1;34m▸\033[0m %s\n' "$1"; }

mkdir -p "$BUDOWA"
cd "$KORZEN"

for ARCH in x86_64 arm64; do
  info "Kompilacja $ARCH"
  swiftc -O -swift-version 5 -parse-as-library -runtime-compatibility-version none \
    -target "$ARCH-apple-macos$MINIMUM" \
    Sources/Core/*.swift Sources/App/*.swift \
    -o "$BUDOWA/Zalaczniki-$ARCH"
done

info "Pakiet aplikacji"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$BUDOWA/Zalaczniki-x86_64" "$BUDOWA/Zalaczniki-arm64" -output "$APP/Contents/MacOS/Zalaczniki"

info "Ikona"
swift scripts/Ikona.swift "$BUDOWA/ikona-1024.png" >/dev/null
ZESTAW="$BUDOWA/AppIcon.iconset"
rm -rf "$ZESTAW" && mkdir -p "$ZESTAW"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUDOWA/ikona-1024.png" --out "$ZESTAW/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUDOWA/ikona-1024.png" --out "$ZESTAW/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ZESTAW" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>Załączniki</string>
  <key>CFBundleDisplayName</key>          <string>Załączniki</string>
  <key>CFBundleIdentifier</key>           <string>pl.plewinscy.zalaczniki</string>
  <key>CFBundleExecutable</key>           <string>Zalaczniki</string>
  <key>CFBundleIconFile</key>             <string>AppIcon</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>CFBundleShortVersionString</key>   <string>$WERSJA</string>
  <key>CFBundleVersion</key>              <string>$WERSJA</string>
  <key>CFBundleDevelopmentRegion</key>    <string>pl</string>
  <key>LSMinimumSystemVersion</key>       <string>$MINIMUM</string>
  <key>LSApplicationCategoryType</key>    <string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key>      <true/>
  <key>ZALDataWydania</key>               <string>$DATA_WYDANIA</string>
  <key>NSHumanReadableCopyright</key>     <string>© 2026 Przemysław Plewiński · Licencja MIT</string>
</dict>
</plist>
PLIST

TOZSAMOSC="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)"
if [ -n "$TOZSAMOSC" ]; then
  info "Podpis: $TOZSAMOSC"
  codesign --force --options runtime --timestamp --sign "$TOZSAMOSC" "$APP"
  codesign --verify --strict --verbose=1 "$APP"
else
  info "Brak certyfikatu Developer ID — podpis ad hoc"
  codesign --force --sign - "$APP"
fi

ZIP="$BUDOWA/Zalaczniki-$WERSJA.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "${1:-}" = "--notaryzuj" ]; then
  info "Notaryzacja (profil: $PROFIL)"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFIL" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
fi

lipo -info "$APP/Contents/MacOS/Zalaczniki"
info "Gotowe: $APP"
info "Do przesłania: $ZIP"
