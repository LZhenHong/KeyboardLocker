# Build Guide

This guide covers the supported build paths for KeyboardLocker, where the resulting app ends up, and how the underlying scripts work.

## Quick Start with Makefile

The easiest way to build the project is using the provided `Makefile`.

```bash
# Create a full, signed, and archived Release build
make build

# Create a faster Release build for local testing
make quick

# Clean all build artefacts and DerivedData caches
make clean

# Copy the latest build from the Build/ directory to /Applications
make install
```

| Command        | Purpose                              | Output Location                    | Underlying Script          |
| -------------- | ------------------------------------ | ---------------------------------- | -------------------------- |
| `make build`   | Optimised release build & archive    | `Build/KeyboardLocker.app`         | `scripts/build_release.sh` |
| `make quick`   | Fast, un-archived development build  | `Build/KeyboardLocker.app`         | `scripts/quick_build.sh`   |
| `make cli`     | Release build of the CLI tool        | `Build/CLI/KeyboardLockerTool`     | `scripts/build_cli.sh`     |
| `make install` | Copy latest build to `/Applications` | `/Applications/KeyboardLocker.app` | -                          |
| `make clean`   | Clean project and cache              | -                                  | -                          |

## Build Scripts

The `make` commands are shortcuts for two Bash scripts located in the `scripts/` directory. You can also run these directly for CI or other automation.

### `scripts/build_release.sh`

This script creates a fully archived and signed Release build, ready for distribution.

- Runs `xcodebuild archive` with standard `mac-application` export options.
- Produces `Build/ReleaseInfo.txt` summarizing the version, build number, and final app size.
- Removes temporary `.build/` artefacts upon completion.

### `scripts/quick_build.sh`

This script builds the Release configuration directly without the archive and export steps. It's ideal for local smoke tests where you need the hardened runtime or want to check menu bar behavior without the full pipeline.

- Invokes `xcodebuild … -configuration Release build`.
- Places the product at `Build/KeyboardLocker.app`.
- Cleans intermediate `Build/Products` and `.build/` folders afterwards.

### `scripts/build_cli.sh`

This script produces the standalone `KeyboardLockerTool` binary used for automation or embedding inside the packaged app.

- Always builds the `KeyboardLockerTool` scheme in the Release configuration.
- Copies the resulting binary to `Build/CLI/KeyboardLockerTool` and makes it executable.
- Removes temporary DerivedData and `Build/Products/CLI` folders to keep the workspace tidy.

## Manual Builds

For complete control, you can invoke `xcodebuild` directly.

```bash
# Build only the CLI target (Release) without the script helper
xcodebuild -project KeyboardLocker.xcodeproj \
           -scheme KeyboardLockerTool \
           -configuration Release build

# Standard Debug/Development build (used during local iteration in Xcode)
xcodebuild -scheme KeyboardLocker -configuration Debug build

# Release configuration build without using the Makefile wrappers
xcodebuild -project KeyboardLocker.xcodeproj \
           -scheme KeyboardLocker \
           -configuration Release build
```

## Installing the App

After any build, the final product is placed in the `Build/` directory.

```bash
# Automatic install using the Makefile helper
make install

# Manual install
open Build/
# Drag KeyboardLocker.app into your /Applications folder and launch it.
```

On first launch, you will be prompted for **Accessibility** access, which is required for the keyboard event tap to function. If you plan to drive the URL schemes from automation tools, macOS will also request **Automation** permission.

## Troubleshooting

- **Build fails during scripts**: Ensure the scripts are executable: `chmod +x scripts/*.sh`.
- **Residual artefacts**: Run `make clean` before rebuilding.
- **Missing signing identity**: Debug builds can run unsigned. For `make build`, ensure your Apple Development certificate is available in your keychain.
- **Command not found (`xcodebuild`)**: Install Xcode and ensure the Command Line Tools are installed by running `xcode-select --install`.

## Requirements

- macOS 13.0+
- Xcode 15.0+ with Command Line Tools
- Apple Development certificate (for signed Release builds via `make build`)
