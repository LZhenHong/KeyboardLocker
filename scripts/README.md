# Build Scripts

This directory contains build automation scripts for KeyboardLocker.

## Scripts Overview

### `build_release.sh`
**Full Release Build Script**
- Creates an optimized archive build
- Exports the app with proper signing
- Generates `ReleaseInfo.txt` with build details
- Recommended for official releases

**Usage:**
```bash
./scripts/build_release.sh
```

**Features:**
- ✅ Full Xcode archive build
- ✅ Optimized for distribution
- ✅ Code signing and symbol stripping
- ✅ Detailed build information
- ✅ Automatic cleanup

### `quick_build.sh`
**Quick Development Build Script**
- Fast build without archive process
- Suitable for testing and development
- Skips some optimization steps for speed

**Usage:**
```bash
./scripts/quick_build.sh
```

**Features:**
- ⚡ Fast build time
- 🔧 Development-focused
- 📦 Direct build output
- 🧹 Automatic cleanup

## Build Requirements

- macOS 13.0+
- Xcode 14.0+
- Valid code signing identity
- Accessibility permissions (for testing)

## Output

Both scripts generate:
- `Build/KeyboardLocker.app` - The built application
- Build information (varies by script)

## Integration

These scripts are integrated with the project's Makefile:

```bash
make build  # Uses build_release.sh
make quick  # Uses quick_build.sh
```

For detailed build instructions, see [../BUILD.md](../BUILD.md).
