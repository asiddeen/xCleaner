#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="xCleaner"
BUNDLE_ID="com.xcleaner.app"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="/tmp/xcleaner-icon.iconset"

export TMPDIR=/tmp
export CLANG_MODULE_CACHE_PATH=/tmp/xcleaner-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/xcleaner-swiftpm-cache

SWIFT_CACHE_FLAGS=(
  --disable-sandbox
  --cache-path /tmp/xcleaner-spm-cache
  -Xswiftc -module-cache-path -Xswiftc /tmp/xcleaner-swift-cache
  -Xcc -fmodules-cache-path=/tmp/xcleaner-clang-cache
)

echo "==> Building $APP_NAME (arm64 release)..."
swift build -c release --arch arm64 "${SWIFT_CACHE_FLAGS[@]}"

BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path "${SWIFT_CACHE_FLAGS[@]}")/$APP_NAME"

echo "==> Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> Generating AppIcon.icns..."
swift -module-cache-path /tmp/xcleaner-swift-cache "$ROOT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>xCleaner</string>
    <key>CFBundleExecutable</key>
    <string>xCleaner</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>xCleaner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
EOF

echo "==> Applying ad-hoc Apple Silicon code signature..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Built: $APP_BUNDLE"
