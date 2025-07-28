import AppKit
import ApplicationServices
import Carbon
import Foundation

// MARK: - Event Handling Helpers

private enum EventTypeFactory {
  static func createEventMask() -> CGEventMask {
    (1 << CGEventType.keyDown.rawValue) |
      (1 << CGEventType.keyUp.rawValue) |
      (1 << CGEventType.flagsChanged.rawValue) |
      (1 << CGEventType.otherMouseDown.rawValue) |
      (1 << CGEventType.otherMouseUp.rawValue)
  }
}

private enum SafeEventHandler {
  static func getFlags(from event: CGEvent) -> CGEventFlags {
    event.flags
  }

  static func getKeycode(from event: CGEvent) -> Int64? {
    event.getIntegerValueField(.keyboardEventKeycode)
  }
}

/// Pure core keyboard locking engine - only handles low-level keyboard interception
/// Business logic and UI concerns are handled by upper layers
public class KeyboardLockCore {
  // MARK: - Singleton

  public static let shared = KeyboardLockCore()

  // MARK: - State Properties (Read-Only)

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var _isLocked = false
  private var _lockedAt: Date?

  // Internal access for callback
  var internalEventTap: CFMachPort? {
    eventTap
  }

  // Constants for hotkey detection
  private let unlockKeyCode: UInt16 = 37 // 'L' key
  private let unlockModifiers: UInt32 = .init(cmdKey | optionKey) // Cmd+Option

  // MARK: - Callbacks for UI Layer

  /// Callback triggered when lock state changes
  public var onLockStateChanged: ((Bool, Date?) -> Void)?

  /// Callback triggered when unlock hotkey is detected
  public var onUnlockHotkeyDetected: (() -> Void)?

  // MARK: - Public Read-Only Properties

  /// Current keyboard lock state
  public var isKeyboardLocked: Bool {
    _isLocked
  }

  /// When keyboard was locked
  public var keyboardLockedAt: Date? {
    _lockedAt
  }

  /// Current lock status for external systems (simplified for Core layer)
  public var basicLockInfo: (isLocked: Bool, lockedAt: Date?) {
    (_isLocked, _lockedAt)
  }

  // MARK: - Initialization

  private init() {
    print("🔑 KeyboardLockCore initialized")
  }

  deinit {
    print("🔑 KeyboardLockCore deallocated")
    forceCleanup()
  }

  // MARK: - Core Locking Methods

  /// Lock keyboard input
  /// - Throws: KeyboardLockError if locking fails
  public func lockKeyboard() throws {
    guard !_isLocked else {
      throw KeyboardLockError.alreadyLocked
    }

    // Use AX API directly.
    let axOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
    guard AXIsProcessTrustedWithOptions(axOptions as CFDictionary) else {
      throw KeyboardLockError.permissionDenied
    }

    try createEventTap()

    _isLocked = true
    _lockedAt = Date()

    // Notify business layer
    onLockStateChanged?(_isLocked, _lockedAt)

    print("🔒 Keyboard locked at \(Date())")
  }

  /// Unlock keyboard input
  public func unlockKeyboard() {
    guard _isLocked else {
      print("⚠️ Keyboard is already unlocked")
      return
    }

    destroyEventTap()

    _isLocked = false
    let wasLockedAt = _lockedAt
    _lockedAt = nil

    // Notify business layer
    onLockStateChanged?(_isLocked, nil)

    if let lockedAt = wasLockedAt {
      let duration = Date().timeIntervalSince(lockedAt)
      print("🔓 Keyboard unlocked after \(formatDuration(duration))")
    }
  }

  /// Toggle lock state
  public func toggleLock() {
    if _isLocked {
      unlockKeyboard()
    } else {
      do {
        try lockKeyboard()
      } catch {
        print("❌ Failed to lock keyboard: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Utility Methods

  /// Get lock duration string
  public func getLockDurationString() -> String? {
    guard let lockedAt = _lockedAt else { return nil }
    let duration = Date().timeIntervalSince(lockedAt)
    return formatDuration(duration)
  }

  /// Force cleanup all resources
  public func forceCleanup() {
    print("🧹 KeyboardLockCore: Force cleanup initiated")

    if _isLocked {
      unlockKeyboard()
    }

    destroyEventTap()
  }

  // MARK: - Private Event Tap Methods

  /// Create event tap for keyboard monitoring
  private func createEventTap() throws {
    let eventMask = EventTypeFactory.createEventMask()

    eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
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
    // Check for unlock hotkey combination
    if type == .keyDown {
      let keycode = SafeEventHandler.getKeycode(from: event)
      let flags = SafeEventHandler.getFlags(from: event)

      if keycode == Int64(unlockKeyCode), flags.contains(.maskCommand),
         flags.contains(.maskAlternate)
      {
        print("🔑 Unlock hotkey detected: ⌘+⌥+L")

        // Notify business layer through callback
        DispatchQueue.main.async {
          self.onUnlockHotkeyDetected?()
        }

        // Don't pass through this event
        return nil
      }
    }

    // Block all keyboard events when locked
    return nil
  }

  // MARK: - Helper Methods

  /// Format duration for display
  private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60

    if minutes > 0 {
      return String(format: "%d:%02d", minutes, seconds)
    } else {
      return String(format: "%ds", seconds)
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

    if let eventTap = core.internalEventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    return Unmanaged.passUnretained(event)
  }

  // Only process events when locked
  guard core.isKeyboardLocked else {
    return Unmanaged.passUnretained(event)
  }

  // Handle the event through core
  return core.handleEvent(type: type, event: event)
}
