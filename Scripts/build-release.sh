#!/bin/bash
# Build snor-oh.app release bundle from Swift Package Manager build output.
# Usage: bash Scripts/build-release.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# --- Configuration ---
APP_NAME="snor-oh"
BUNDLE_ID="com.snoroh.swift"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"
EXECUTABLE="SnorOhSwift"

BUILD_DIR="$PROJECT_DIR/.build/release-app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

# --- Clean ---
echo "==> Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# --- Build ---
echo "==> Building release binary..."
swift build -c release --arch arm64 2>&1 | tail -3

BINARY="$PROJECT_DIR/.build/release/$EXECUTABLE"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

# --- Assemble .app bundle ---
echo "==> Assembling $APP_NAME.app..."

# Copy binary — name MUST match CFBundleExecutable in Info.plist
cp "$BINARY" "$MACOS_DIR/$EXECUTABLE"
chmod +x "$MACOS_DIR/$EXECUTABLE"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$CONTENTS/Info.plist"

# Write PkgInfo (standard macOS app marker)
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Copy resources
if [ -d "$PROJECT_DIR/Resources/Sprites" ]; then
    cp -R "$PROJECT_DIR/Resources/Sprites" "$RESOURCES_DIR/Sprites"
    echo "    Sprites: $(ls "$RESOURCES_DIR/Sprites" | wc -l | tr -d ' ') files"
fi

if [ -d "$PROJECT_DIR/Resources/Scripts" ]; then
    cp -R "$PROJECT_DIR/Resources/Scripts" "$RESOURCES_DIR/Scripts"
    echo "    Scripts: copied (incl. MCP server + shell hooks)"
fi

if [ -d "$PROJECT_DIR/Resources/Sounds" ]; then
    cp -R "$PROJECT_DIR/Resources/Sounds" "$RESOURCES_DIR/Sounds"
fi

# Copy app icon if exists
if [ -d "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset" ]; then
    # For now, just copy the xcassets — a proper build would compile them with actool
    echo "    Note: App icon requires actool compilation (skipped in SPM build)"
fi

# Remove .DS_Store files
find "$APP_BUNDLE" -name ".DS_Store" -delete 2>/dev/null || true

# --- Code Sign ---
echo "==> Signing with ad-hoc identity + entitlements..."
codesign --force --sign - \
    --entitlements "$PROJECT_DIR/Entitlements.plist" \
    --deep \
    "$APP_BUNDLE"

# --- Verify ---
echo ""
echo "=== Build Complete ==="
echo "App:     $APP_BUNDLE"
echo "Size:    $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""

# Verify code signature
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E "^(Identifier|Format|Signature|TeamIdentifier|Sealed)" || true

echo ""
echo "Contents:"
find "$APP_BUNDLE" -maxdepth 4 -type d | sed "s|$APP_BUNDLE/||" | sort

echo ""
echo "To run: open \"$APP_BUNDLE\""
echo "To create DMG: hdiutil create -volname \"$APP_NAME\" -srcfolder \"$APP_BUNDLE\" -ov -format UDZO \"$BUILD_DIR/$APP_NAME-$VERSION.dmg\""
