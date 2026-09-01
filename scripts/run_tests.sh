#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🧪 Regenerating Xcode project with XcodeGen..."
xcodegen generate

echo "🚀 Running Jigglypuff test suite (Integration & Smoke Tests)..."
xcodebuild test \
  -project Jigglypuff.xcodeproj \
  -scheme JigglypuffTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES

echo ""
echo "✅ All integration and smoke tests passed successfully!"
