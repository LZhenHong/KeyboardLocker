# KeyboardLocker Build Guide

This project provides multiple ways to build the release version of KeyboardLocker.

## 🚀 Quick Start

The simplest way is to use Make commands:

```bash
make build
```

This will generate `KeyboardLocker.app` in the `Build/` folder.

## 📋 Available Build Commands

### Make Commands (Recommended)

```bash
# Full release build (recommended)
make build

# Quick build (for testing)
make quick  

# Clean build artifacts
make clean

# Build and install to /Applications
make install

# Open Build folder in Finder
make open

# Show built app information
make info

# Show help
make help
```

### Direct Script Usage

```bash
# Full archive build (generates optimized app)
./scripts/build_release.sh

# Quick build (skips archive step)
./scripts/quick_build.sh
```

### Using Xcode Command Line

```bash
# Manual build
xcodebuild -project KeyboardLocker.xcodeproj \
           -scheme KeyboardLocker \
           -configuration Release \
           build
```

## 📂 Output Files

After building, you'll find in the `Build/` folder:

- `KeyboardLocker.app` - The executable application
- `ReleaseInfo.txt` - Build information (full build only)

## 🔧 Build Options Comparison

| Method                       | Speed | Optimization | Archive | Recommended Use     |
| ---------------------------- | ----- | ------------ | ------- | ------------------- |
| `make build`                 | Slow  | Highest      | ✅       | Official Release    |
| `make quick`                 | Fast  | High         | ❌       | Quick Testing       |
| `./scripts/build_release.sh` | Slow  | Highest      | ✅       | Official Release    |
| `./scripts/quick_build.sh`   | Fast  | High         | ❌       | Development Testing |

## 🚛 Installation Instructions

After building, there are several ways to install the app:

### Automatic Installation
```bash
make install
```

### Manual Installation
1. Open `Build/` folder: `make open`
2. Drag `KeyboardLocker.app` to `/Applications` folder
3. Grant accessibility permissions when first launched

## 🛠 Troubleshooting

### Build Failures
- Ensure Xcode is installed and up to date
- Check for project compilation errors
- Try cleaning and rebuilding: `make clean && make build`

### Permission Errors
- Ensure scripts have execute permissions: `chmod +x scripts/*.sh`
- Check if there's sufficient disk space

### Version Information Shows as Unknown
- Check if `Info.plist` file is properly configured
- Try rebuilding: `make clean && make build`

## 📊 Build Information

Use `make info` to view:
- Application version
- Build number
- File size
- Last modified time

## 🔄 Continuous Integration

These scripts are also suitable for CI/CD environments:

```bash
# CI script example
make clean
make build
make info
```

## 📝 Notes

- Building requires macOS 13.0+ development environment
- Ensure Xcode Command Line Tools are installed
- First build may take longer to download dependencies
- Generated app is code-signed and optimized, ready for distribution
