# Keyboard Locker - GitHub Copilot Instructions

## Project Overview

This is a macOS status bar application built with Swift and SwiftUI using the modern MenuBarExtra API that allows users to quickly lock and unlock their keyboard to prevent accidental input.

## Development Requirements

### Core Development Standards
- **Internationalization**: Maintain internationalization (i18n) throughout the project with English comments
- **Logging**: Log messages do not require internationalization
- **Documentation**: All markdown documentation must be updated to reflect the latest project status and written in English
- **Code Quality**: Follow Swift API design guidelines and modern SwiftUI patterns

## Project Structure

```
KeyboardLocker/
├── KeyboardLocker/
│   ├── KeyboardLockerApp.swift      # Main app entry point using MenuBarExtra
│   ├── ContentView.swift           # Main interface displayed in popover
│   ├── SettingsView.swift          # Settings configuration interface
│   ├── AboutView.swift             # About page with app information
│   ├── KeyboardLockManager.swift   # Core keyboard locking functionality
│   ├── Info.plist                  # App configuration (LSUIElement: true)
│   ├── KeyboardLocker.entitlements # Security entitlements
│   └── Assets.xcassets/            # App assets and icons
├── KeyboardLocker.xcodeproj/        # Xcode project files
├── README.md                        # Project documentation
└── .gitignore                      # Git ignore rules
```

## Key Technologies

- **Swift 5.7+** - Primary programming language
- **SwiftUI** - UI framework for all interfaces
- **MenuBarExtra** - Modern status bar management API (macOS 13.0+)
- **AppKit** - macOS system integration
- **NSEvent** - Global keyboard event monitoring
- **UserNotifications** - Modern notification framework

## Architecture Guidelines

### App Lifecycle
- The app runs as a status bar utility (no Dock icon)
- `LSUIElement: true` in Info.plist prevents Dock appearance
- Uses modern SwiftUI App protocol with MenuBarExtra
- Requires macOS 13.0+ for MenuBarExtra API support

### Status Bar Management
- MenuBarExtra with `.window` style for popover interface
- Status bar icon: `lock.shield` system symbol
- Click shows main interface popover with lock controls
- No context menu needed with modern design

### Keyboard Locking System
- `KeyboardLockManager` handles global event monitoring as ObservableObject
- Uses `NSEvent.addGlobalMonitorForEvents` for keyboard interception
- Unlock combination: `⌘ + ⌥ + L`
- Supports auto-lock with configurable timeouts
- Managed as @StateObject in KeyboardLockerApp and injected via @EnvironmentObject

### UI Components
- **ContentView**: Main interface with lock/unlock toggle and quick settings
- **SettingsView**: Comprehensive settings for auto-lock, notifications, startup
- **AboutView**: App information and feature list
- All views use macOS 13.0+ compatible SwiftUI components with MenuBarExtra integration

## Coding Standards

### SwiftUI Best Practices
- Use `@StateObject` for KeyboardLockManager in main app
- Use `@EnvironmentObject` to access manager in child views
- Use `@AppStorage` for user preferences persistence
- Prefer composition over inheritance
- Use modern SwiftUI patterns for macOS 13.0+

### Event Handling
- Global keyboard monitoring requires accessibility permissions
- Always check for existing monitors before creating new ones
- Properly clean up event monitors on app termination
- Use weak references to prevent retain cycles

### Settings Management
- Use `@AppStorage` for user preferences with automatic persistence
- Support these settings:
  - `autoLockDuration`: Auto-lock timeout (15, 30, 60 minutes, or never)
  - `showNotifications`: Toggle for lock/unlock notifications

### Error Handling
- Handle permission requests gracefully
- Provide user-friendly error messages
- Fall back to basic functionality if advanced features fail

## Security Considerations

### Entitlements
```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
```

### Permissions Required
- **Accessibility Access**: For global keyboard event monitoring
- **User Notifications**: For lock status notifications (optional)

### Privacy
- No data collection or external network requests
- All settings stored locally using UserDefaults/@AppStorage
- Keyboard events are only monitored, not logged or transmitted

## Development Guidelines

### Code Style
- Use descriptive variable and function names
- Comment complex keyboard event handling logic
- Separate UI logic from business logic
- Follow Swift API design guidelines
- Use modern SwiftUI patterns and MenuBarExtra API

### Testing Considerations
- Test on macOS 13.0+ (minimum deployment target)
- Verify accessibility permission handling
- Test keyboard event interception thoroughly
- Ensure proper cleanup on app termination

### Common Pitfalls to Avoid
- Don't use macOS 14.0+ only APIs without version checks
- Always remove event monitors before adding new ones
- Handle permission denied scenarios gracefully
- Don't block the main thread with keyboard monitoring
- Ensure MenuBarExtra compatibility with different macOS versions

## Feature Implementation Notes

### Modern MenuBarExtra Implementation
- Use MenuBarExtra with `.window` style for native popover experience
- No need for traditional NSStatusBar management
- Cleaner architecture with SwiftUI-first approach
- Automatic window management and positioning

### Auto-Lock Feature
- Implement with Timer or DispatchQueue.asyncAfter
- Reset timer on any keyboard/mouse activity
- Provide clear visual feedback when auto-lock is active

### Notification System
- Use UserNotifications framework (not deprecated NSUserNotification)
- Request permission before showing notifications
- Make notifications informative but not intrusive

### Login Items
- Use ServiceManagement framework for login item management
- Handle user permission properly
- Provide clear feedback about startup status

## Debugging Tips

- Use Console.app to view system logs
- Test accessibility permissions in System Preferences
- Use Xcode's debugger for SwiftUI view hierarchy
- Monitor keyboard events with careful logging (remove in production)

## Performance Considerations

- MenuBarExtra provides optimized status bar updates
- Use efficient event filtering for keyboard monitoring
- Lazy load settings windows
- Optimize SwiftUI view updates with proper @StateObject/@EnvironmentObject usage
- Minimal memory footprint with modern SwiftUI patterns

## System Requirements

- **Minimum macOS Version**: 13.0 (for MenuBarExtra support)
- **Recommended macOS Version**: 13.0 or later
- **Xcode Version**: 14.0 or later for MenuBarExtra development
- **Swift Version**: 5.7 or later

Remember: This app prioritizes user privacy, system integration, and reliable keyboard locking functionality while maintaining a clean, native macOS experience using modern SwiftUI APIs.
