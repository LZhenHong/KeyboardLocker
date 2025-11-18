# KeyboardLocker Makefile
# 
# Available commands:
#   make build      - Build release version to Build directory
#   make quick      - Quick build without archive
#   make clean      - Clean build artifacts
#   make cli        - Build CLI helper binary to Build/CLI
#   make install    - Install app to /Applications
#   make open       - Open Build directory in Finder
#   make info       - Show app information

.PHONY: build quick clean install open info cli help

# Default target
all: build

# Full release build with archive
build:
	@echo "🚀 Building KeyboardLocker Release (Archive)..."
	@./scripts/build_release.sh

# Quick build without archive
quick:
	@echo "⚡ Quick building KeyboardLocker..."
	@./scripts/quick_build.sh

# Build CLI helper
cli:
	@echo "🛠 Building KeyboardLocker CLI (Release)..."
	@./scripts/build_cli.sh

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf Build/.build Build/Products .build DerivedData
	@echo "✅ Clean complete"

# Install to Applications folder
install: build
	@echo "📦 Installing KeyboardLocker to /Applications..."
	@if [ -d "/Applications/KeyboardLocker.app" ]; then \
		rm -rf "/Applications/KeyboardLocker.app"; \
	fi
	@cp -R "Build/KeyboardLocker.app" "/Applications/"
	@echo "✅ KeyboardLocker installed to /Applications"
	@echo "💡 You may need to grant accessibility permissions"

# Open Build directory in Finder
open:
	@open Build

# Show app information
info:
	@if [ -d "Build/KeyboardLocker.app" ]; then \
		echo "📊 KeyboardLocker App Information:"; \
		echo "   Location: Build/KeyboardLocker.app"; \
		echo "   Version: $$(plutil -p Build/KeyboardLocker.app/Contents/Info.plist | grep CFBundleShortVersionString | cut -d'"' -f4 2>/dev/null || echo 'Unknown')"; \
		echo "   Build: $$(plutil -p Build/KeyboardLocker.app/Contents/Info.plist | grep CFBundleVersion | cut -d'"' -f4 2>/dev/null || echo 'Unknown')"; \
		echo "   Size: $$(du -sh Build/KeyboardLocker.app | cut -f1)"; \
		echo "   Modified: $$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' Build/KeyboardLocker.app)"; \
	else \
		echo "❌ No built app found. Run 'make build' first."; \
	fi

# Show help
help:
	@echo "KeyboardLocker Build System"
	@echo "=========================="
	@echo ""
	@echo "Available commands:"
	@echo "  make build      Build release version to Build directory (recommended)"
	@echo "  make quick      Quick build without archive (faster)"
	@echo "  make clean      Clean build artifacts"
	@echo "  make cli        Build CLI helper binary (Release)"
	@echo "  make install    Install app to /Applications"
	@echo "  make open       Open Build directory in Finder"
	@echo "  make info       Show app information"
	@echo "  make help       Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make            # Same as 'make build'"
	@echo "  make build      # Full release build"
	@echo "  make quick      # Quick build for testing"
	@echo "  make install    # Build and install to /Applications"
