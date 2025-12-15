import AppKit
import Common
import CoreGraphics
import Foundation
import os

// Use refcon to bridge C callback to Swift instance since CGEventTap requires C function pointer
private func eventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let refcon else {
    return Unmanaged.passUnretained(event)
  }

  let engine = Unmanaged<LockEngine>.fromOpaque(refcon).takeUnretainedValue()

  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    print("Event tap disabled by system, attemping to re-enable...")

    if let eventTap = engine.eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    return Unmanaged.passUnretained(event)
  }

  return engine.handleEvent(proxy: proxy, type: type, event: event)
}

public class LockEngine {
  public static let shared = LockEngine()

  public enum LockEngineError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case eventTapCreationFailed
    case runLoopSourceCreationFailed
    case alreadyLocked

    public var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied:
        "Accessibility permission is required to lock keyboard and mouse input."
      case .eventTapCreationFailed:
        "Failed to create event tap. This may indicate a permissions issue or system restriction."
      case .runLoopSourceCreationFailed:
        "Failed to create run loop source for event tap."
      case .alreadyLocked:
        "The keyboard is already locked by another session."
      }
    }

    public var recoverySuggestion: String? {
      switch self {
      case .accessibilityPermissionDenied:
        "Open System Settings → Privacy & Security → Accessibility and enable access for this application."
      case .eventTapCreationFailed:
        "Try restarting the application. If the problem persists, check Accessibility permissions in System Settings."
      case .runLoopSourceCreationFailed:
        "This is a system-level error. Please contact support if it persists."
      case .alreadyLocked:
        "Wait for the current lock to be released or expire."
      }
    }
  }

  static let eventMasks: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue) |
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue)

  private static let runLoopSourceOrder: CFIndex = 0
  private static let autoRepeatFlagValue: Int64 = 1

  // Unfair lock for thread-safe state access (higher performance than DispatchQueue)
  private let stateLock = OSAllocatedUnfairLock()

  // fileprivate access required for C callback to re-enable tap on system timeout
  fileprivate var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var autoUnlockTimer: DispatchSourceTimer?

  // Private state storage protected by stateLock
  private var _isLocked = false
  private var _lockStartedAt: Date?
  private var _autoUnlockTargetDate: Date?
  private var _activeSettings: KeyboardLockerSettings = .default

  // Thread-safe public accessors
  public var isLocked: Bool {
    withLock { _isLocked }
  }

  public var lockStartedAt: Date? {
    withLock { _lockStartedAt }
  }

  public var autoUnlockTargetDate: Date? {
    withLock { _autoUnlockTargetDate }
  }

  private init() {}

  // Helper method to safely execute critical sections with automatic lock management
  private func withLock<T>(_ block: () throws -> T) rethrows -> T {
    stateLock.lock()
    defer { stateLock.unlock() }
    return try block()
  }

  public func lock(settings: KeyboardLockerSettings = .default) throws {
    // Check lock status atomically
    try withLock {
      guard !_isLocked else {
        throw LockEngineError.alreadyLocked
      }

      // Verify Accessibility permission before attempting to create event tap
      guard AccessibilityManager.hasPermission() else {
        throw LockEngineError.accessibilityPermissionDenied
      }

      _activeSettings = settings
    }

    // Event tap creation must happen on main thread
    try startEventTap()
    markLocked()
  }

  private func startEventTap() throws {
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: Self.eventMasks,
      callback: eventTapCallback,
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    ) else {
      throw LockEngineError.eventTapCreationFailed
    }
    eventTap = tap

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, Self.runLoopSourceOrder) else {
      throw LockEngineError.runLoopSourceCreationFailed
    }
    runLoopSource = source

    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func markLocked() {
    withLock {
      _isLocked = true
      _lockStartedAt = Date()
    }

    configureAutoUnlockTimerIfNeeded()
    LockStateBroadcaster.broadcast(isLocked: true)
    print("LockEngine: Locked")
  }

  private func configureAutoUnlockTimerIfNeeded() {
    cancelAutoUnlockTimer()

    let (timeout, startDate) = withLock {
      (_activeSettings.autoUnlockPolicy.timeout, _lockStartedAt)
    }

    guard let timeout, timeout > 0, let startDate else {
      return
    }

    withLock {
      _autoUnlockTargetDate = startDate.addingTimeInterval(timeout)
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler { [weak self] in
      self?.unlock()
    }
    timer.resume()
    autoUnlockTimer = timer
  }

  private func cancelAutoUnlockTimer() {
    autoUnlockTimer?.cancel()
    autoUnlockTimer = nil

    withLock {
      _autoUnlockTargetDate = nil
    }
  }

  public func unlock() {
    // Check lock status atomically
    let shouldUnlock = withLock { _isLocked }
    guard shouldUnlock else {
      return
    }

    cancelAutoUnlockTimer()
    teardownEventTap()
    resetLockState()
  }

  private func teardownEventTap() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
      eventTap = nil
    }

    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
      runLoopSource = nil
    }
  }

  private func resetLockState() {
    withLock {
      _isLocked = false
      _lockStartedAt = nil
      _autoUnlockTargetDate = nil
    }

    LockStateBroadcaster.broadcast(isLocked: false)
    print("LockEngine: Unlocked")
  }

  fileprivate func handleEvent(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    guard isLocked else {
      return Unmanaged.passUnretained(event)
    }

    if shouldTriggerUnlock(for: type, event: event) {
      DispatchQueue.main.async { [weak self] in
        self?.unlock()
      }
    }

    return nil
  }

  private func shouldTriggerUnlock(for type: CGEventType, event: CGEvent) -> Bool {
    let hotkey = withLock { _activeSettings.unlockHotkey }

    switch type {
    case .keyDown:
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      guard hotkey.matches(keyCode: keyCode, flags: event.flags) else {
        return false
      }

      let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == Self.autoRepeatFlagValue
      return !isAutoRepeat

    case .flagsChanged:
      let keyCode = hotkey.keyCode
      return CGEventSource.keyState(.hidSystemState, key: keyCode)

    default:
      return false
    }
  }

  public func lockDuration(at date: Date = Date()) -> TimeInterval? {
    let start = withLock { _lockStartedAt }
    guard let start else {
      return nil
    }
    return max(0, date.timeIntervalSince(start))
  }

  public func remainingAutoUnlockTime(at date: Date = Date()) -> TimeInterval? {
    let deadline = withLock { _autoUnlockTargetDate }
    guard let deadline else {
      return nil
    }
    return max(0, deadline.timeIntervalSince(date))
  }
}
