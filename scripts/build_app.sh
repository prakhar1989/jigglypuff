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

# Prefer a stable signing identity so TCC grants (Accessibility, Microphone)
# survive rebuilds. Ad-hoc signatures change with every build, which silently
# invalidates those grants.
SIGNING_HASH="$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/^ *[0-9]+\) +([0-9A-Fa-f]+) .*/\1/')"
if [ -n "$SIGNING_HASH" ]; then
    echo "🔏 Signing with stable identity: $SIGNING_HASH"
    SIGN_SETTINGS=(CODE_SIGN_IDENTITY="$SIGNING_HASH" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES)
else
    echo "⚠️  No 'Apple Development' signing identity found — falling back to ad-hoc signing."
    echo "    Accessibility/Microphone permissions will need to be re-granted after EVERY rebuild."
    echo "    Create one in Xcode → Settings → Accounts → Manage Certificates → '+' → Apple Development."
    SIGN_SETTINGS=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES)
fi

xcodebuild -project Jiggypuff.xcodeproj \
           -scheme Jiggypuff \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR/DerivedData" \
           build \
           "${SIGN_SETTINGS[@]}"

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
