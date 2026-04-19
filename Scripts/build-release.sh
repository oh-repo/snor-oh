#!/bin/bash
# Build snor-oh.app universal release bundle from Swift Package Manager.
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

# --- Build universal binary (arm64 + x86_64) ---
echo "==> Building arm64..."
swift build -c release --arch arm64 2>&1 | tail -1

echo "==> Building x86_64..."
swift build -c release --arch x86_64 2>&1 | tail -1

ARM_BINARY="$PROJECT_DIR/.build/apple/Products/Release/$EXECUTABLE"
X86_BINARY="$PROJECT_DIR/.build/apple/Products/Release/$EXECUTABLE"

# SPM puts arch-specific builds in different locations
ARM_BINARY="$PROJECT_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE"
X86_BINARY="$PROJECT_DIR/.build/x86_64-apple-macosx/release/$EXECUTABLE"

if [ ! -f "$ARM_BINARY" ]; then
    echo "ERROR: arm64 binary not found at $ARM_BINARY"
    exit 1
fi
if [ ! -f "$X86_BINARY" ]; then
    echo "ERROR: x86_64 binary not found at $X86_BINARY"
    exit 1
fi

echo "==> Creating universal binary with lipo..."
lipo -create "$ARM_BINARY" "$X86_BINARY" -output "$MACOS_DIR/$EXECUTABLE"
chmod +x "$MACOS_DIR/$EXECUTABLE"

# Verify
ARCHS=$(lipo -archs "$MACOS_DIR/$EXECUTABLE")
echo "    Architectures: $ARCHS"

# --- Assemble .app bundle ---
echo "==> Assembling $APP_NAME.app..."

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
echo "Archs:   $ARCHS"
echo ""

# Verify code signature
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E "^(Identifier|Format|Signature|TeamIdentifier|Sealed)" || true

echo ""
echo "Contents:"
find "$APP_BUNDLE" -maxdepth 4 -type d | sed "s|$APP_BUNDLE/||" | sort

echo ""
echo "To run: open \"$APP_BUNDLE\""
echo "To create DMG: hdiutil create -volname \"$APP_NAME\" -srcfolder \"$APP_BUNDLE\" -ov -format UDZO \"$BUILD_DIR/$APP_NAME-$VERSION.dmg\""
