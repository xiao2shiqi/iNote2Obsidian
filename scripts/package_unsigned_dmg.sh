#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/NativeApp"
BUILD_DIR="$APP_DIR/.build/debug"
PRODUCT_NAME="iNote2Obsidian"
EXECUTABLE_NAME="iNote2ObsidianApp"
BUNDLE_ID="com.xiao2shiqi.iNote2Obsidian"
VERSION="${1:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)}"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/stage"
APP_BUNDLE="$STAGE_DIR/$PRODUCT_NAME.app"
DMG_PATH="$DIST_DIR/$PRODUCT_NAME-$VERSION-unsigned.dmg"

mkdir -p "$DIST_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

swift build --package-path "$APP_DIR"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"

ln -sfn /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$PRODUCT_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG created at: $DMG_PATH"
