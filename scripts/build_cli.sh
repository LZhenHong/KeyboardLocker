#!/bin/bash

# Quick build script for the KeyboardLocker CLI target
# Usage: ./scripts/build_cli.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="KeyboardLocker"
SCHEME_NAME="KeyboardLockerTool"
DERIVED_DATA_DIR="$PROJECT_DIR/.build-cli"
PRODUCTS_DIR="$PROJECT_DIR/Build/Products/CLI"
OUTPUT_DIR="$PROJECT_DIR/Build/CLI"
BINARY_NAME="KeyboardLockerTool"

# Always build Release; CLI is distributed via app bundle/test environment.
CONFIGURATION="Release"

echo "🚀 Building $SCHEME_NAME ($CONFIGURATION)..."

cd "$PROJECT_DIR"

xcodebuild -project "$PROJECT_NAME.xcodeproj" \
           -scheme "$SCHEME_NAME" \
           -configuration "$CONFIGURATION" \
           -derivedDataPath "$DERIVED_DATA_DIR" \
           build \
           SYMROOT="$PRODUCTS_DIR" \
           -quiet

CLI_PRODUCT_PATH="$PRODUCTS_DIR/$CONFIGURATION/$SCHEME_NAME"

mkdir -p "$OUTPUT_DIR"

if [ -f "$CLI_PRODUCT_PATH" ]; then
  cp "$CLI_PRODUCT_PATH" "$OUTPUT_DIR/$BINARY_NAME"
  chmod +x "$OUTPUT_DIR/$BINARY_NAME"

  echo "✅ Success! CLI binary is ready."
  echo "📍 Location: $OUTPUT_DIR/$BINARY_NAME"
  echo "💡 Example: $OUTPUT_DIR/$BINARY_NAME --help"
else
  echo "❌ Build failed - CLI binary not found at $CLI_PRODUCT_PATH"
  exit 1
fi

# Clean up intermediate files to keep Build/ tidy
rm -rf "$PRODUCTS_DIR"
rm -rf "$DERIVED_DATA_DIR"

echo "🧹 Temporary build artifacts cleaned up."
