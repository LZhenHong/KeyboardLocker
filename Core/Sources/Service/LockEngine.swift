import AppKit
import Common
import CoreGraphics
import Foundation
import os

struct AutoUnlockSchedule: Equatable {
  let deadline: Date
  let delay: TimeInterval

  static func make(
    timeout: TimeInterval?,
    referenceDate: Date,
    currentDate: Date
  ) -> Self? {
    guard
      let timeout,
      timeout.isFinite,
      timeout > 0,
      referenceDate.timeIntervalSinceReferenceDate.isFinite,
      currentDate.timeIntervalSinceReferenceDate.isFinite
    else {
      return nil
    }

    let deadline = referenceDate.addingTimeInterval(timeout)
    guard deadline.timeIntervalSinceReferenceDate.isFinite else {
      return nil
    }

    return Self(
      deadline: deadline,
      delay: max(0, deadline.timeIntervalSince(currentDate))
    )
  }
}

/// Use refcon to bridge C callback to Swift instance since CGEventTap requires C function pointer
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
    LockEngine.logger.warning("Event tap disabled by system, attempting to re-enable")

    if let eventTap = engine.eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    return Unmanaged.passUnretained(event)
  }

  return engine.handleEvent(proxy: proxy, type: type, event: event)
}

public class LockEngine {
  public static let shared = LockEngine()

  static let logger = Logger(subsystem: SharedConstants.machServiceName, category: "LockEngine")

  public enum LockEngineError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case eventTapCreationFailed
    case runLoopSourceCreationFailed

    public var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied:
        "Accessibility permission is required to lock keyboard input."
      case .eventTapCreationFailed:
        "Failed to create event tap. This may indicate a permissions issue or system restriction."
      case .runLoopSourceCreationFailed:
        "Failed to create run loop source for event tap."
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
      }
    }
  }

  /// Mouse and system-defined events remain available under the keyboard-only product contract.
  static let eventMasks: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue) |
    (1 << CGEventType.flagsChanged.rawValue)

  private static let runLoopSourceOrder: CFIndex = 0
  private static let autoRepeatFlagValue: Int64 = 1

  /// Unfair lock for thread-safe state access (higher performance than DispatchQueue)
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

  /// Thread-safe public accessors
  public var isLocked: Bool {
    withLock { _isLocked }
  }

  var lockStartedAt: Date? {
    withLock { _lockStartedAt }
  }

  var autoUnlockTargetDate: Date? {
    withLock { _autoUnlockTargetDate }
  }

  private init() {}

  /// Helper method to safely execute critical sections with automatic lock management
  private func withLock<T>(_ block: () throws -> T) rethrows -> T {
    stateLock.lock()
    defer { stateLock.unlock() }
    return try block()
  }

  public func lock(settings: KeyboardLockerSettings = .default) throws {
    // The lock is a single global state; locking while already locked is a no-op
    // success (idempotent), but we still adopt the latest settings.
    let alreadyLocked: Bool = withLock {
      _activeSettings = settings
      return _isLocked
    }

    if alreadyLocked {
      // Re-arm the auto-unlock timer / hotkey against the new settings.
      configureAutoUnlockTimerIfNeeded()
      return
    }

    // Verify Accessibility permission before attempting to create event tap.
    guard AccessibilityManager.hasPermission() else {
      throw LockEngineError.accessibilityPermissionDenied
    }

    // Event tap creation must happen on main thread
    try startEventTap()
    markLocked()
  }

  /// Updates the active settings. If a lock is running, changes take effect immediately
  /// (e.g. a new auto-unlock timeout re-arms the timer); otherwise they seed the next lock.
  public func updateSettings(_ settings: KeyboardLockerSettings) {
    let isLocked: Bool = withLock {
      _activeSettings = settings
      return _isLocked
    }

    if isLocked {
      configureAutoUnlockTimerIfNeeded()
    }
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
    LockStateBroadcaster.broadcast()
    Self.logger.info("Locked")
  }

  private func configureAutoUnlockTimerIfNeeded() {
    cancelAutoUnlockTimer()

    let (timeout, isLocked) = withLock {
      (_activeSettings.autoUnlockPolicy.timeout, _isLocked)
    }

    // Re-arming starts a fresh timeout window without changing the duration
    // of the lock session tracked by `_lockStartedAt`.
    let referenceDate = Date()
    guard
      isLocked,
      let schedule = AutoUnlockSchedule.make(
        timeout: timeout,
        referenceDate: referenceDate,
        currentDate: Date()
      )
    else {
      return
    }

    withLock {
      _autoUnlockTargetDate = schedule.deadline
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + schedule.delay)
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

    LockStateBroadcaster.broadcast()
    Self.logger.info("Unlocked")
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

    default:
      return false
    }
  }

  func lockDuration(at date: Date = Date()) -> TimeInterval? {
    let start = withLock { _lockStartedAt }
    guard let start else {
      return nil
    }
    return max(0, date.timeIntervalSince(start))
  }

  func remainingAutoUnlockTime(at date: Date = Date()) -> TimeInterval? {
    let deadline = withLock { _autoUnlockTargetDate }
    guard let deadline else {
      return nil
    }
    return max(0, deadline.timeIntervalSince(date))
  }
}
