#!/bin/bash

# KeyboardLocker Release Build Script
# This script builds a release version of the app and copies it to the Build folder

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/Build"
DERIVED_DATA_DIR="$PROJECT_DIR/.build"

# Project configuration
PROJECT_NAME="KeyboardLocker"
SCHEME_NAME="KeyboardLocker"
CONFIGURATION="Release"
ARCHIVE_PATH="$DERIVED_DATA_DIR/KeyboardLocker.xcarchive"

echo -e "${BLUE}🚀 Starting KeyboardLocker Release Build${NC}"
echo -e "${YELLOW}Project Directory: $PROJECT_DIR${NC}"
echo -e "${YELLOW}Build Directory: $BUILD_DIR${NC}"

# Create Build directory if it doesn't exist
if [ ! -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}📁 Creating Build directory...${NC}"
    mkdir -p "$BUILD_DIR"
fi

# Clean previous builds
echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
if [ -d "$DERIVED_DATA_DIR" ]; then
    rm -rf "$DERIVED_DATA_DIR"
fi
mkdir -p "$DERIVED_DATA_DIR"

# Check if Xcode project exists
if [ ! -f "$PROJECT_DIR/$PROJECT_NAME.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}❌ Error: Xcode project not found at $PROJECT_DIR/$PROJECT_NAME.xcodeproj${NC}"
    exit 1
fi

echo -e "${YELLOW}🔨 Building archive...${NC}"
# Build archive
xcodebuild archive \
    -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -quiet

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Archive build failed${NC}"
    exit 1
fi

echo -e "${YELLOW}📦 Exporting app...${NC}"
# Export the app from archive
EXPORT_OPTIONS_PLIST="$DERIVED_DATA_DIR/ExportOptions.plist"

# Create export options plist
cat > "$EXPORT_OPTIONS_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
EOF

EXPORT_PATH="$DERIVED_DATA_DIR/Export"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    -quiet

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Export failed${NC}"
    exit 1
fi

# Copy the app to Build directory
echo -e "${YELLOW}📋 Copying app to Build directory...${NC}"
if [ -d "$EXPORT_PATH/$PROJECT_NAME.app" ]; then
    # Remove existing app if it exists
    if [ -d "$BUILD_DIR/$PROJECT_NAME.app" ]; then
        rm -rf "$BUILD_DIR/$PROJECT_NAME.app"
    fi
    
    cp -R "$EXPORT_PATH/$PROJECT_NAME.app" "$BUILD_DIR/"
    
    echo -e "${GREEN}✅ Success! App built and copied to Build directory${NC}"
    echo -e "${GREEN}📍 Location: $BUILD_DIR/$PROJECT_NAME.app${NC}"
    
    # Get app info
    APP_VERSION=$(defaults read "$BUILD_DIR/$PROJECT_NAME.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "Unknown")
    APP_BUILD=$(defaults read "$BUILD_DIR/$PROJECT_NAME.app/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "Unknown")
    APP_SIZE=$(du -sh "$BUILD_DIR/$PROJECT_NAME.app" | cut -f1)
    
    echo -e "${BLUE}📊 Build Information:${NC}"
    echo -e "${BLUE}   Version: $APP_VERSION${NC}"
    echo -e "${BLUE}   Build: $APP_BUILD${NC}"
    echo -e "${BLUE}   Size: $APP_SIZE${NC}"
    
    # Create a release info file
    cat > "$BUILD_DIR/ReleaseInfo.txt" << EOF
KeyboardLocker Release Build
============================
Build Date: $(date)
Version: $APP_VERSION
Build Number: $APP_BUILD
Configuration: $CONFIGURATION
Size: $APP_SIZE

App Location: $BUILD_DIR/$PROJECT_NAME.app

To install:
1. Drag $PROJECT_NAME.app to /Applications folder
2. Grant accessibility permissions when prompted
3. Launch from Applications or Spotlight

For more information, see README.md
EOF

    echo -e "${GREEN}📄 Release info saved to $BUILD_DIR/ReleaseInfo.txt${NC}"
    
else
    echo -e "${RED}❌ Error: Exported app not found at $EXPORT_PATH/$PROJECT_NAME.app${NC}"
    exit 1
fi

# Clean up temporary files
echo -e "${YELLOW}🧹 Cleaning up temporary files...${NC}"
rm -rf "$DERIVED_DATA_DIR"

echo -e "${GREEN}🎉 Build complete! Your release app is ready in the Build directory.${NC}"
