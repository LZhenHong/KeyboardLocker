import AppKit
import Carbon

/// Pure core keyboard locking engine - only handles low-level keyboard interception
/// Business logic and UI concerns are handled by upper layers
public class KeyboardLockCore {
  // MARK: - Singleton

  public static let shared = KeyboardLockCore()

  // MARK: - State Properties (Read-Only)

  var eventTap: CFMachPort?

  private var runLoopSource: CFRunLoopSource?

  /// Current keyboard lock state
  public private(set) var isLocked = false

  /// When keyboard was locked
  public private(set) var lockedAt: Date?

  // MARK: - Hotkey Configuration

  /// Unlock hotkey configuration
  public var unlockHotkey: HotkeyConfiguration = .defaultHotkey()

  // MARK: - Callbacks for UI Layer

  /// Callback triggered when lock state changes
  public var onLockStateChanged: ((Bool, Date?) -> Void)?

  /// Callback triggered when unlock hotkey is detected
  public var onUnlockHotkeyDetected: (() -> Void)?

  // MARK: - Hotkey State Tracking

  private static let relevantModifierMask: CGEventFlags = [
    .maskCommand,
    .maskAlternate,
    .maskShift,
    .maskControl,
  ]

  static let eventMasks: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue) |
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue)

  // MARK: - Initialization

  private init() {}

  deinit {
    forceCleanup()
  }

  // MARK: - Hotkey Configuration Methods

  /// Configure unlock hotkey combination
  /// - Parameter hotkey: The hotkey configuration
  public func configureUnlockHotkey(_ hotkey: HotkeyConfiguration) {
    guard !isLocked else {
      print("⚠️ Cannot change hotkey while keyboard is locked")
      return
    }

    unlockHotkey = hotkey
    print("🔧 Unlock hotkey configured: \(hotkey.description)")
  }

  /// Configure unlock hotkey combination (convenience method)
  /// - Parameters:
  ///   - keyCode: The key code for the unlock key
  ///   - modifiers: The modifier flags (Command, Option, etc.)
  ///   - displayString: The display string for the hotkey
  public func configureUnlockHotkey(keyCode: UInt16, modifiers: UInt32, displayString: String) {
    let hotkey = HotkeyConfiguration(keyCode: keyCode, modifierFlags: modifiers, displayString: displayString)
    configureUnlockHotkey(hotkey)
  }

  /// Reset unlock hotkey to default (Cmd+Option+L)
  public func resetUnlockHotkeyToDefault() {
    configureUnlockHotkey(.defaultHotkey())
  }

  // MARK: - Core Locking Methods

  /// Lock keyboard input
  /// - Throws: KeyboardLockError if locking fails
  public func lockKeyboard() throws {
    guard !isLocked else {
      throw KeyboardLockError.alreadyLocked
    }

    // Check accessibility permission using PermissionHelper
    guard PermissionHelper.checkAccessibilityPermission(promptUser: true) else {
      throw KeyboardLockError.permissionDenied
    }

    try createEventTap()

    isLocked = true
    lockedAt = Date()

    // Notify business layer
    onLockStateChanged?(isLocked, lockedAt)
  }

  /// Unlock keyboard input
  public func unlockKeyboard() {
    guard isLocked else {
      return
    }

    destroyEventTap()

    isLocked = false
    lockedAt = nil

    // Notify business layer
    onLockStateChanged?(isLocked, nil)
  }

  /// Toggle lock state
  public func toggleLock() {
    if isLocked {
      unlockKeyboard()
    } else {
      do {
        try lockKeyboard()
      } catch {
        print("❌ Failed to lock keyboard: \(error.localizedDescription)")
      }
    }
  }

  /// Force cleanup all resources
  public func forceCleanup() {
    print("🧹 KeyboardLockCore: Force cleanup initiated")

    unlockKeyboard()
    destroyEventTap()
  }

  // MARK: - Private Event Tap Methods

  /// Create event tap for keyboard monitoring
  private func createEventTap() throws {
    eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: Self.eventMasks,
      callback: globalEventCallback,
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )

    guard let eventTap else {
      throw KeyboardLockError.eventTapCreationFailed
    }

    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    guard let runLoopSource else {
      throw KeyboardLockError.runLoopSourceCreationFailed
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    print("🎯 Event tap created and enabled")
  }

  /// Destroy event tap and cleanup resources
  private func destroyEventTap() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
      print("🎯 Event tap disabled and invalidated")
    }

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      self.runLoopSource = nil
      print("🎯 Run loop source removed")
    }
  }

  /// Handle keyboard events (internal for callback)
  func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if shouldTriggerUnlock(for: type, event: event) {
      print("🔑 Unlock hotkey pressed: \(unlockHotkey.displayString)")

      DispatchQueue.main.async {
        self.onUnlockHotkeyDetected?()
      }
    }

    // Block all events from propagating while locked
    return nil
  }

  private func shouldTriggerUnlock(for type: CGEventType, event: CGEvent) -> Bool {
    guard event.flags.intersection(Self.relevantModifierMask) == unlockHotkey.eventModifierFlags else {
      return false
    }

    switch type {
    case .keyDown:
      let keycodeValue = event.getIntegerValueField(.keyboardEventKeycode)
      guard keycodeValue >= 0, keycodeValue <= Int64(UInt16.max) else {
        return false
      }

      let eventKeyCode = CGKeyCode(UInt16(keycodeValue))
      guard eventKeyCode == unlockHotkey.keyCode else {
        return false
      }

      let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
      return !isAutoRepeat

    case .flagsChanged:
      if unlockHotkey.keyCode == 0 {
        return true
      }

      return CGEventSource.keyState(.hidSystemState, key: unlockHotkey.keyCode)

    default:
      return false
    }
  }
}

// MARK: - Global Event Callback

private func globalEventCallback(
  proxy _: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let refcon else {
    return Unmanaged.passUnretained(event)
  }

  let core = Unmanaged<KeyboardLockCore>.fromOpaque(refcon).takeUnretainedValue()

  // Handle tap disabled event
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    print("⚠️ Event tap disabled by system, attempting to re-enable...")

    if let eventTap = core.eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    return Unmanaged.passUnretained(event)
  }

  // Only process events when locked
  guard core.isLocked else {
    return Unmanaged.passUnretained(event)
  }

  // Handle the event through core
  return core.handleEvent(type: type, event: event)
}
