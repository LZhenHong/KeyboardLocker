# Build Guide

## Quick Build

```bash
# Recommended: Full release build
make build

# Quick development build
make quick
```

## Build Commands

| Command        | Purpose           | Speed | Optimization |
| -------------- | ----------------- | ----- | ------------ |
| `make build`   | Release build     | Slow  | Highest      |
| `make quick`   | Development build | Fast  | Basic        |
| `make clean`   | Clean build files | -     | -            |
| `make install` | Build and install | Slow  | Highest      |

## Manual Build

```bash
# Using Xcode command line
xcodebuild -project KeyboardLocker.xcodeproj \
           -scheme KeyboardLocker \
           -configuration Release

# Using scripts directly  
./scripts/build_release.sh    # Full build
./scripts/quick_build.sh      # Quick build
```

## Output

Built app will be in `Build/KeyboardLocker.app`

## Installation

```bash
# Automatic
make install

# Manual
open Build/
# Drag KeyboardLocker.app to /Applications
```

## Troubleshooting

- **Build fails**: Try `make clean && make build`
- **Permission errors**: Run `chmod +x scripts/*.sh`
- **Missing Xcode**: Install Xcode and command line tools

## Requirements

- macOS 13.0+
- Xcode 14.0+
- Command Line Tools
