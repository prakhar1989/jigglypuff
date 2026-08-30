#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

BUILD_DIR="$PROJECT_ROOT/build"
APP_PATH="$BUILD_DIR/Jiggypuff.app"
DMG_PATH="$BUILD_DIR/Jiggypuff.dmg"

# 1. Build the app bundle if it doesn't exist or force rebuild
echo "🚀 Ensuring release build is up-to-date..."
./scripts/build_app.sh

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Jiggypuff.app not found in $BUILD_DIR"
    exit 1
fi

echo "📦 Packaging Jiggypuff into DMG installer..."
rm -f "$DMG_PATH"

if command -v create-dmg &> /dev/null; then
    echo "✨ Using 'create-dmg' for styled DMG layout..."
    create-dmg \
      --volname "Jiggypuff Installer" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 128 \
      --icon "Jiggypuff.app" 150 190 \
      --hide-extension "Jiggypuff.app" \
      --app-drop-link 450 190 \
      --no-internet-enable \
      "$DMG_PATH" \
      "$APP_PATH" || true
fi

# Fallback if create-dmg is not installed or failed
if [ ! -f "$DMG_PATH" ]; then
    echo "ℹ️  Using native macOS 'hdiutil' to create DMG..."
    STAGING_DIR="$BUILD_DIR/dmg_staging"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
    
    cp -R "$APP_PATH" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"
    
    hdiutil create \
      -volname "Jiggypuff Installer" \
      -srcfolder "$STAGING_DIR" \
      -ov \
      -format UDZO \
      "$DMG_PATH"
      
    rm -rf "$STAGING_DIR"
fi

echo ""
echo "🎉 DMG successfully created!"
echo "📍 Location: $DMG_PATH"
echo "📏 Size: $(du -sh "$DMG_PATH" | awk '{print $1}')"
