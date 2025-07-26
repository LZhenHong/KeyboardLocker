import ApplicationServices
import Carbon
import Foundation

/// Core keyboard locking functionality that can be shared between main app and CLI
public class KeyboardLockCore {
  // MARK: - Singleton

  public static let shared = KeyboardLockCore()

  // MARK: - Private Properties

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var isLocked = false
  private var lockedAt: Date?
  private var autoLockTimer: Timer?
  private var autoLockInterval: TimeInterval = 0 // 0 means disabled

  // MARK: - Public Properties

  /// Current lock status
  public var lockStatus: LockStatus {
    return LockStatus(
      isLocked: isLocked,
      lockedAt: lockedAt,
      autoLockEnabled: autoLockInterval > 0,
      autoLockInterval: Int(autoLockInterval / 60)
    )
  }

  /// Whether keyboard is currently locked
  public var isKeyboardLocked: Bool {
    return isLocked
  }

  // MARK: - Initialization

  private init() {
    // Private initializer for singleton
  }

  deinit {
    unlockKeyboard()
    stopAutoLockTimer()
  }

  // MARK: - Public Methods

  /// Lock the keyboard with comprehensive event blocking
  /// - Throws: CoreError if locking fails
  /// - Returns: True if successfully locked, false if already locked
  @discardableResult
  public func lockKeyboard() throws -> Bool {
    guard !isLocked else {
      throw CoreError.alreadyLocked
    }

    // Validate permissions first
    try PermissionHelper.validatePermissions()

    // Create event tap to intercept keyboard events
    let eventMask = (1 << CGEventType.keyDown.rawValue) |
      (1 << CGEventType.keyUp.rawValue) |
      (1 << CGEventType.flagsChanged.rawValue)

    eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(eventMask),
      callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
        return KeyboardLockCore.eventCallback(
          proxy: proxy, type: type, event: event, refcon: refcon
        )
      },
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )

    guard let eventTap = eventTap else {
      throw CoreError.eventTapCreationFailed
    }

    // Create run loop source and add to current run loop
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    guard let runLoopSource = runLoopSource else {
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
      throw CoreError.eventTapCreationFailed
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

    // Enable the event tap
    CGEvent.tapEnable(tap: eventTap, enable: true)

    // Update state
    isLocked = true
    lockedAt = Date()

    print("🔒 Keyboard locked successfully")
    return true
  }

  /// Unlock the keyboard
  /// - Returns: True if successfully unlocked, false if not locked
  @discardableResult
  public func unlockKeyboard() -> Bool {
    guard isLocked else {
      return false
    }

    // Disable event tap
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }

    // Remove run loop source
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    }

    // Invalidate and clean up
    if let eventTap = eventTap {
      CFMachPortInvalidate(eventTap)
    }

    eventTap = nil
    runLoopSource = nil
    isLocked = false
    lockedAt = nil

    print("🔓 Keyboard unlocked successfully")
    return true
  }

  /// Toggle keyboard lock status
  /// - Throws: CoreError if operation fails
  /// - Returns: New lock status (true = locked, false = unlocked)
  @discardableResult
  public func toggleLock() throws -> Bool {
    if isLocked {
      unlockKeyboard()
      return false
    } else {
      try lockKeyboard()
      return true
    }
  }

  // MARK: - Auto-Lock Feature

  /// Set auto-lock timer
  /// - Parameter interval: Time interval in seconds, 0 to disable
  public func setAutoLockInterval(_ interval: TimeInterval) {
    autoLockInterval = interval

    if interval > 0 {
      startAutoLockTimer()
    } else {
      stopAutoLockTimer()
    }
  }

  /// Start auto-lock timer
  private func startAutoLockTimer() {
    stopAutoLockTimer() // Stop existing timer

    guard autoLockInterval > 0 else { return }

    autoLockTimer = Timer.scheduledTimer(withTimeInterval: autoLockInterval, repeats: false) {
      [weak self] _ in
      guard let self = self, !self.isLocked else { return }

      do {
        try self.lockKeyboard()
        print("🔒 Auto-lock activated after \(Int(self.autoLockInterval / 60)) minutes")
      } catch {
        print("❌ Auto-lock failed: \(error.localizedDescription)")
      }
    }
  }

  /// Stop auto-lock timer
  private func stopAutoLockTimer() {
    autoLockTimer?.invalidate()
    autoLockTimer = nil
  }

  /// Reset auto-lock timer (call this on user activity)
  public func resetAutoLockTimer() {
    guard autoLockInterval > 0, !isLocked else { return }
    startAutoLockTimer()
  }

  // MARK: - Event Handling

  /// Check if the given event represents the unlock hotkey combination
  /// Default: Cmd + Option + L
  private func isUnlockHotkey(event: CGEvent) -> Bool {
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Check for Cmd + Option + L (keycode 37 is 'L')
    return flags.contains(.maskCommand) && flags.contains(.maskAlternate)
      && keyCode == CoreConstants.defaultUnlockKeyCode
  }

  /// Event callback function for event tap
  private static func eventCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
  ) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return nil }
    let keyboardLock = Unmanaged<KeyboardLockCore>.fromOpaque(refcon).takeUnretainedValue()

    // Handle tap disabled case
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap = keyboardLock.eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return nil
    }

    // Only process events when locked
    guard keyboardLock.isLocked else {
      return Unmanaged.passRetained(event)
    }

    // Check for unlock hotkey before blocking
    if keyboardLock.isUnlockHotkey(event: event) {
      keyboardLock.unlockKeyboard()
      return nil // Block this event too
    }

    // Block all other keyboard events when locked
    return nil
  }

  // MARK: - Utility Methods

  /// Get formatted lock duration string
  public func getLockDurationString() -> String? {
    guard let lockedAt = lockedAt else { return nil }

    let duration = Date().timeIntervalSince(lockedAt)
    let minutes = Int(duration / 60)
    let seconds = Int(duration.truncatingRemainder(dividingBy: 60))

    if minutes > 0 {
      return "\(minutes)m \(seconds)s"
    } else {
      return "\(seconds)s"
    }
  }

  /// Force cleanup (for emergency situations)
  public func forceCleanup() {
    unlockKeyboard()
    stopAutoLockTimer()
  }
}
