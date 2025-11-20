import AppKit
import CoreGraphics
import Foundation

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
    case eventTapCreationFailed
    case runLoopSourceCreationFailed

    public var errorDescription: String? {
      switch self {
      case .eventTapCreationFailed:
        "Failed to create event tap. Check Accessibility permissions."
      case .runLoopSourceCreationFailed:
        "Failed to create run loop source for event tap."
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

  // fileprivate access required for C callback to re-enable tap on system timeout
  fileprivate var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var autoUnlockTimer: DispatchSourceTimer?
  private var activeSettings: KeyboardLockerSettings = .default

  // Thread-safe property access could be improved, but for this MVP we assume main thread usage for XPC handling
  public private(set) var isLocked = false
  public private(set) var lockStartedAt: Date?
  public private(set) var autoUnlockTargetDate: Date?

  private init() {}

  public func lock(settings: KeyboardLockerSettings = .default) throws {
    guard !isLocked else {
      return
    }

    activeSettings = settings
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
    isLocked = true
    lockStartedAt = Date()
    configureAutoUnlockTimerIfNeeded()

    print("LockEngine: Locked")
  }

  private func configureAutoUnlockTimerIfNeeded() {
    cancelAutoUnlockTimer()
    guard let timeout = activeSettings.autoUnlockPolicy.timeout, timeout > 0,
          let startDate = lockStartedAt
    else {
      return
    }

    autoUnlockTargetDate = startDate.addingTimeInterval(timeout)

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
    autoUnlockTargetDate = nil
  }

  public func unlock() {
    guard isLocked else {
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
    isLocked = false
    lockStartedAt = nil
    autoUnlockTargetDate = nil

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
    switch type {
    case .keyDown:
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      guard activeSettings.unlockHotkey.matches(keyCode: keyCode, flags: event.flags) else {
        return false
      }

      let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == Self.autoRepeatFlagValue
      return !isAutoRepeat

    case .flagsChanged:
      let keyCode = activeSettings.unlockHotkey.keyCode
      return CGEventSource.keyState(.hidSystemState, key: keyCode)

    default:
      return false
    }
  }

  public func lockDuration(at date: Date = Date()) -> TimeInterval? {
    guard let start = lockStartedAt else {
      return nil
    }
    return max(0, date.timeIntervalSince(start))
  }

  public func remainingAutoUnlockTime(at date: Date = Date()) -> TimeInterval? {
    guard let deadline = autoUnlockTargetDate else {
      return nil
    }
    return max(0, deadline.timeIntervalSince(date))
  }
}
