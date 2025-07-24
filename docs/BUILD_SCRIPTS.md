# Build Scripts

Build automation scripts for KeyboardLocker.

## Scripts

### `build_release.sh`
Full release build with archive and optimization.
```bash
./scripts/build_release.sh
```

**Features:**
- Xcode archive build
- Code signing and optimization
- Generates `ReleaseInfo.txt`
- Ready for distribution

### `quick_build.sh`  
Fast development build without archive.
```bash
./scripts/quick_build.sh
```

**Features:**
- Quick compilation
- Skips optimization steps
- Good for testing

## Usage

```bash
# Recommended: Use Makefile
make build     # Full release build
make quick     # Quick development build

# Direct script usage
./scripts/build_release.sh
./scripts/quick_build.sh
```

## Output

Built applications are placed in `Build/KeyboardLocker.app`

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

For detailed build instructions, see [BUILD.md](BUILD.md).
