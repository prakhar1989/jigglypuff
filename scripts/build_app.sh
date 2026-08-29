#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🎙️ Generating Xcode Project with XcodeGen..."
xcodegen generate

echo "🔨 Building Jiggypuff.app in Release configuration..."
BUILD_DIR="$PROJECT_ROOT/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild -project Jiggypuff.xcodeproj \
           -scheme Jiggypuff \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR/DerivedData" \
           build \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=YES

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/Jiggypuff.app"

if [ -d "$APP_PATH" ]; then
    cp -R "$APP_PATH" "$BUILD_DIR/Jiggypuff.app"
    echo "✨ Successfully built Jiggypuff.app!"
    echo "📍 App bundle located at: $BUILD_DIR/Jiggypuff.app"
    echo ""
    echo "To launch Jiggypuff, run:"
    echo "  open $BUILD_DIR/Jiggypuff.app"
    echo ""
    echo "Or copy to Applications folder:"
    echo "  cp -R $BUILD_DIR/Jiggypuff.app /Applications/"
else
    echo "❌ Build failed. App bundle not found."
    exit 1
fi
