# Developer Guide

This document provides technical guidance for contributors and maintainers of the Keyboard Locker project.

## Project Architecture

### Modern SwiftUI Architecture

Keyboard Locker uses modern SwiftUI architecture patterns, designed specifically for macOS 13.0+:

```swift
@main
struct KeyboardLockerApp: App {
    @StateObject private var keyboardLockManager = KeyboardLockManager()
    
    var body: some Scene {
        MenuBarExtra("Keyboard Locker", systemImage: "lock.shield") {
            ContentView()
                .environmentObject(keyboardLockManager)
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Core Components

#### 1. KeyboardLockManager (ObservableObject)
```swift
class KeyboardLockManager: ObservableObject {
    @Published var isLocked: Bool = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalHotkeyMonitor: Any?
    
    func lockKeyboard() { 
        // Enhanced with comprehensive error handling
        // Includes exception recovery mechanisms
    }
    func unlockKeyboard() { /* Implementation */ }
    private func handleKeyEvent() { /* Global event handling */ }
    private func setupGlobalHotkey() { /* Global hotkey support */ }
    private func recoverFromError() { /* Error recovery */ }
}
```

#### 2. ContentView (Permission-Aware Interface)
```swift
struct ContentView: View {
    @State private var hasAccessibilityPermission = false
    @EnvironmentObject var keyboardManager: KeyboardLockManager
    
    var body: some View {
        if hasAccessibilityPermission {
            authorizedView  // Main functionality interface
        } else {
            unauthorizedView  // Permission setup interface
        }
    }
}
```

#### 3. MenuBarExtra Integration
- Uses `.window` style for native popover experience
- Automatically handles window positioning and lifecycle
- No manual NSStatusBar management required
- Permission-aware interface switching

#### 4. Permission Management System
- Real-time permission status checking using `AXIsProcessTrusted()`
- Automatic interface switching between authorized and unauthorized states
- Direct system settings integration with URL schemes
- User-friendly permission setup guidance

#### 5. State Management
- `@StateObject` manages KeyboardLockManager at App level
- `@EnvironmentObject` passes state between views
- `@AppStorage` automatically persists user settings
- Permission state tracked with `@State` variables

## Development Environment Setup

### Requirements
- **macOS 13.0+** - For development and testing, supports MenuBarExtra API
- **Xcode 14.0+** - MenuBarExtra API and modern Swift features support
- **Swift 5.7+** - Modern language features support

### Project Configuration
1. Clone repository to local machine
2. Open `KeyboardLocker.xcodeproj` in Xcode
3. Ensure deployment target is set to macOS 13.0
4. Build and run (⌘+R)

### Permission Configuration
Development and testing require the following system permissions:
- **Accessibility Permission** - System Preferences > Security & Privacy > Accessibility
  - Add Xcode or built app to the allowed list
  - This is required for keyboard event monitoring
- **Notification Permission** - Automatically requested on first app launch
  - User can choose to allow or deny
  - Does not affect core functionality

## Code Conventions

### Localization Development
Using modern .xcstrings format:

```swift
// Localized string usage
Text(LocalizationKey.appTitle.localized)

// Dynamic version information
Text(Bundle.main.localizedVersionString)

// Parameterized localization
String(format: "about.version.format".localized, version, build)
```

### State Management Best Practices
```swift
// ✅ Recommended: Use @StateObject for lifecycle management
@StateObject private var manager = KeyboardLockManager()

// ✅ Recommended: Use @EnvironmentObject for state passing
@EnvironmentObject var keyboardManager: KeyboardLockManager

// ✅ Recommended: Use @AppStorage for settings persistence
@AppStorage("showNotifications") private var showNotifications = true

// ✅ Recommended: Permission state tracking
@State private var hasAccessibilityPermission = false
```

### Permission Management Implementation
```swift
// Check permission status
private func checkPermissionStatus() {
    hasAccessibilityPermission = AXIsProcessTrusted()
}

// Open system settings
private func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}

// Permission-aware UI
var body: some View {
    if hasAccessibilityPermission {
        MainInterfaceView()
    } else {
        PermissionSetupView()
    }
}
```

### UI State Management
```swift
// Status-based button styling
.background(isKeyboardLocked ? Color.red : Color.green)

// Real-time permission checking
.onAppear {
    checkPermissionStatus()
}
```

### Error Handling
```swift
// ✅ Gracefully handle permission requests
func requestAccessibilityPermission() -> Bool {
    let trusted = AXIsProcessTrusted()
    if !trusted {
        // Show user-friendly error message
        showPermissionAlert()
    }
    return trusted
}
```

### Memory Management
```swift
// ✅ Use weak self to avoid retain cycles
eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
    self?.handleKeyEvent(event)
}

// ✅ Properly clean up resources
deinit {
    if let monitor = eventMonitor {
        NSEvent.removeMonitor(monitor)
    }
}
```

## Testing Guide

### Functional Testing Checklist
1. **Keyboard Locking System Tests**
   - ✅ Verify all keyboard input is properly intercepted
   - ✅ Confirm unlock combination `⌘+⌥+L` works correctly
   - ✅ Test global lock hotkey `⌘+⌥+⇧+L` functionality
   - ✅ Ensure mouse operations are unaffected
   - ✅ Test multiple lock/unlock cycles
   - ✅ Verify error recovery mechanisms
   - ✅ Test exception handling during keyboard operations

2. **Menu Bar Integration Tests**
   - ✅ Verify MenuBarExtra icon displays correctly
   - ✅ Test popover interface responsiveness and layout
   - ✅ Check status indicator updates
   - ✅ Verify interface language switching

3. **Settings Persistence Tests**
   - ✅ Verify @AppStorage correctly saves settings
   - ✅ Test settings persist after app restart
   - ✅ Check multi-language settings saving

4. **Notification System Tests**
   - ✅ Test notification permission request flow
   - ✅ Verify lock/unlock notifications display
   - ✅ Test notification toggle controls
   - ✅ Check multi-language notification content

### Permission Testing
- ✅ Test graceful degradation without Accessibility permissions
- ✅ Verify permission request UI and guidance
- ✅ Check optional notification permission handling
- ✅ Confirm permission status detection accuracy

## Deployment

### Build Configuration
- **Debug**: Development and testing, includes debug symbols
- **Release**: Production version, optimized performance

### Code Signing
```bash
# Developer identity
codesign --deep --force --verify --verbose --sign "Developer ID Application: Your Name" KeyboardLocker.app

# Verify signature
codesign --verify --verbose KeyboardLocker.app
```

### Distribution
1. Archive project in Xcode
2. Export app through Organizer
3. Choose appropriate distribution method (Developer ID, App Store, etc.)

## Troubleshooting

### Common Issues and Solutions

#### MenuBarExtra Not Showing
- **Check**: macOS version is ≥ 13.0
- **Check**: Info.plist has `LSUIElement` set to `true`
- **Check**: MenuBarExtra code syntax is correct
- **Solution**: Restart app or re-authorize permissions

#### Keyboard Events Not Intercepted
- **Check**: Accessibility permission has been granted
- **Check**: App shows main interface (not permission setup screen)
- **Check**: CFMachPort event tap is properly created
- **Check**: Event handling logic correctly filters unlock combination
- **Solution**: Re-authorize Accessibility permissions, restart app

#### Permission Setup Screen Always Showing
- **Check**: Accessibility permission is actually granted in System Settings
- **Check**: App is listed and enabled in Privacy & Security > Accessibility
- **Check**: Permission checking logic is called after settings change
- **Solution**: Click "Check Permission Status" button after granting permission

#### Button Colors Not Updating
- **Check**: State binding between KeyboardLockManager and ContentView
- **Check**: @Published and @EnvironmentObject are properly configured
- **Check**: UI updates are called on main queue
- **Solution**: Verify ObservableObject implementation and state flow

#### Localized Strings Not Displaying
- **Check**: .xcstrings files are added to project Target
- **Check**: Localization key names are correct
- **Check**: System language settings match
- **Solution**: Re-add .xcstrings files to project

#### Settings Not Persisting
- **Check**: @AppStorage property wrapper usage is correct
- **Check**: UserDefaults key names are consistent
- **Check**: Data types are compatible
- **Solution**: Clear app data and reconfigure

### Debug Tips
```swift
// Check permission status
print("Accessibility trusted: \(AXIsProcessTrusted())")

// Debug keyboard event handling
private func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    
    #if DEBUG
    print("Key event - Code: \(keyCode), Flags: \(flags)")
    #endif
    
    // Handle unlock combination
    if flags.contains([.maskCommand, .maskAlternate]), keyCode == 37 {
        print("Unlock combination detected")
        return Unmanaged.passRetained(event)
    }
    
    return nil  // Block other events
}

// Debug permission state changes
func checkPermissionStatus() {
    let previousState = hasAccessibilityPermission
    hasAccessibilityPermission = AXIsProcessTrusted()
    
    #if DEBUG
    print("Permission state changed: \(previousState) -> \(hasAccessibilityPermission)")
    #endif
}
```

## Contribution Guidelines

### Code Contributions
1. Fork the project
2. Create a feature branch
3. Implement changes and add tests
4. Submit a Pull Request

### Commit Conventions
```
feat: add new feature
fix: fix bug
docs: update documentation
style: code formatting changes
refactor: refactor code
test: add tests
chore: miscellaneous updates
```

### Code Review Checklist
- [ ] Code follows project conventions
- [ ] Added necessary comments
- [ ] Updated relevant documentation
- [ ] Tested new functionality
- [ ] Checked for memory leaks
- [ ] Verified permission handling

## Related Resources

- [SwiftUI MenuBarExtra Documentation](https://developer.apple.com/documentation/swiftui/menubarextra)
- [NSEvent Global Monitoring](https://developer.apple.com/documentation/appkit/nsevent)
- [UserNotifications Framework](https://developer.apple.com/documentation/usernotifications)
- [macOS Accessibility](https://developer.apple.com/documentation/applicationservices/axuielementref)
