#!/bin/bash

# Quick Release Build Script for KeyboardLocker
# Usage: ./quick_build.sh

set -e

# Get project directory (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Building KeyboardLocker Release..."

# Change to project directory
cd "$PROJECT_DIR"

# Build and export in one step using xcodebuild
xcodebuild -project KeyboardLocker.xcodeproj \
           -scheme KeyboardLocker \
           -configuration Release \
           -derivedDataPath .build \
           build \
           SYMROOT="Build/Products" \
           -quiet

# Copy the app to Build directory
mkdir -p Build
if [ -d "Build/Products/Release/KeyboardLocker.app" ]; then
    rm -rf "Build/KeyboardLocker.app" 2>/dev/null || true
    cp -R "Build/Products/Release/KeyboardLocker.app" "Build/"
    
    # Clean up intermediate files
    rm -rf "Build/Products"
    rm -rf ".build"
    
    echo "✅ Success! KeyboardLocker.app is ready in Build directory"
    echo "📍 Size: $(du -sh Build/KeyboardLocker.app | cut -f1)"
else
    echo "❌ Build failed - app not found"
    exit 1
fi
