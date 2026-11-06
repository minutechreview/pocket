#!/bin/zsh
# Builds Pocket.app (the NotchClip package) (release), signs it, and optionally installs it to /Applications.
# Usage: scripts/build-app.sh [--install]
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Pocket.app"
VERSION="0.1.0"

cd "$ROOT"
swift build -c release --product NotchClip

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchClip "$APP/Contents/MacOS/NotchClip"

# App icon
ICONSET="$ROOT/build/AppIcon.iconset"
if [[ ! -f "$ROOT/build/AppIcon.icns" ]]; then
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift scripts/make-icon.swift "$ROOT/build/icon-1024.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ROOT/build/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$ROOT/build/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pocket</string>
  <key>CFBundleDisplayName</key><string>Pocket</string>
  <key>CFBundleIdentifier</key><string>com.minutechbuilds.notchclip</string>
  <key>CFBundleExecutable</key><string>NotchClip</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Rayan Abdul Cader</string>
</dict>
</plist>
PLIST

# Sign with a stable identity so the Accessibility permission survives rebuilds; fall back to ad-hoc.
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x NotchClip 2>/dev/null || true
  rm -rf /Applications/NotchClip.app /Applications/Pocket.app
  cp -R "$APP" /Applications/Pocket.app
  open /Applications/Pocket.app
  echo "Installed to /Applications and launched"
fi
