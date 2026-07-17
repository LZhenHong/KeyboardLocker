import AppKit
import Carbon
import Common
@preconcurrency import CoreGraphics
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

struct LockRuntimeState: Equatable {
  private(set) var activeSettings: KeyboardLockerSettings = .default
  private(set) var allowsControlCUnlock = false
  private(set) var autoUnlockTargetDate: Date?
  private(set) var isLocked = false
  private(set) var startedAt: Date?

  mutating func begin(
    settings: KeyboardLockerSettings,
    allowsControlCUnlock: Bool,
    at date: Date
  ) -> LockRequestOutcome {
    guard !isLocked else {
      return .alreadyLocked
    }

    activeSettings = settings
    self.allowsControlCUnlock = allowsControlCUnlock
    autoUnlockTargetDate = nil
    isLocked = true
    startedAt = date
    return .acquired
  }

  mutating func updateSettings(_ settings: KeyboardLockerSettings) {
    activeSettings = settings
  }

  mutating func setAutoUnlockTargetDate(_ date: Date?) {
    autoUnlockTargetDate = date
  }

  mutating func end() {
    allowsControlCUnlock = false
    autoUnlockTargetDate = nil
    isLocked = false
    startedAt = nil
  }
}

struct UnlockGestureMatcher {
  static let controlCKeyCode = CGKeyCode(kVK_ANSI_C)

  private static let controlCHotkey = KeyboardLockerSettings.Hotkey(
    keyCode: controlCKeyCode,
    modifierFlags: [.maskControl]
  )

  static func matches(
    type: CGEventType,
    keyCode: CGKeyCode,
    flags: CGEventFlags,
    isAutoRepeat: Bool,
    configuredHotkey: KeyboardLockerSettings.Hotkey,
    allowsControlCUnlock: Bool
  ) -> Bool {
    guard type == .keyDown, !isAutoRepeat else {
      return false
    }

    if configuredHotkey.matches(keyCode: keyCode, flags: flags) {
      return true
    }

    return allowsControlCUnlock
      && controlCHotkey.matches(keyCode: keyCode, flags: flags)
  }
}

enum EventTapInstallationError: Error, Equatable {
  case eventTapCreationFailed
  case eventTapEnableFailed
  case runLoopSourceCreationFailed
}

/// Acquires an event tap and its run-loop source as one transaction. Any incomplete installation
/// is rolled back in reverse order, so callers never retain a half-installed input filter.
struct EventTapInstallation<Tap, Source> {
  let tap: Tap
  let source: Source

  static func make(
    createTap: () -> Tap?,
    createSource: (Tap) -> Source?,
    attachSource: (Source) -> Void,
    enableTap: (Tap) -> Void,
    isTapEnabled: (Tap) -> Bool,
    detachSource: (Source) -> Void,
    invalidateTap: (Tap) -> Void
  ) throws -> Self {
    guard let tap = createTap() else {
      throw EventTapInstallationError.eventTapCreationFailed
    }

    var source: Source?
    var committed = false
    defer {
      if !committed {
        if let source {
          detachSource(source)
        }
        invalidateTap(tap)
      }
    }

    guard let createdSource = createSource(tap) else {
      throw EventTapInstallationError.runLoopSourceCreationFailed
    }
    source = createdSource
    attachSource(createdSource)
    enableTap(tap)

    guard isTapEnabled(tap) else {
      throw EventTapInstallationError.eventTapEnableFailed
    }

    committed = true
    return Self(tap: tap, source: createdSource)
  }
}

/// Use refcon to bridge C callback to Swift instance since CGEventTap requires C function pointer
private func eventTapCallback(
  proxy _: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let refcon else {
    return Unmanaged.passUnretained(event)
  }

  let engine = Unmanaged<LockEngine>.fromOpaque(refcon).takeUnretainedValue()
  // The callback runs on the main run loop where the tap is installed. Make that runtime
  // guarantee explicit so every event-tap resource remains isolated to `MainActor`.
  return MainActor.assumeIsolated {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      return engine.handleDisabledEvent(event)
    }

    return engine.handleEvent(type: type, event: event)
  }
}

@MainActor
public final class LockEngine {
  public static let shared = LockEngine()

  static let logger = Logger(subsystem: SharedConstants.machServiceName, category: "LockEngine")

  public enum LockEngineError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case eventTapCreationFailed
    case eventTapEnableFailed
    case runLoopSourceCreationFailed

    public var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied:
        "Accessibility permission is required to lock keyboard input."
      case .eventTapCreationFailed:
        "Failed to create event tap. This may indicate a permissions issue or system restriction."
      case .eventTapEnableFailed:
        "The keyboard event tap was created but could not be enabled."
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
      case .eventTapEnableFailed:
        "Check Accessibility permissions in System Settings, then try locking again."
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

  private var eventTap: CFMachPort?
  private var eventTapGeneration: UInt64 = 0
  private var runLoopSource: CFRunLoopSource?
  private var autoUnlockTimer: DispatchSourceTimer?
  private var runtimeState = LockRuntimeState()

  public var isLocked: Bool {
    runtimeState.isLocked
  }

  var lockStartedAt: Date? {
    runtimeState.startedAt
  }

  var autoUnlockTargetDate: Date? {
    runtimeState.autoUnlockTargetDate
  }

  private init() {}

  @discardableResult
  public func lock(
    settings: KeyboardLockerSettings = .default,
    allowsControlCUnlock: Bool = false
  ) throws -> LockRequestOutcome {
    // A duplicate request is a strict no-op. In particular, it must not extend the authoritative
    // auto-unlock deadline merely because another wrapper repeated the same global intent.
    if runtimeState.isLocked {
      return .alreadyLocked
    }

    // Verify Accessibility permission before attempting to create event tap.
    guard AccessibilityManager.hasPermission() else {
      throw LockEngineError.accessibilityPermissionDenied
    }

    // Event tap creation must happen on main thread
    try startEventTap()
    let outcome = runtimeState.begin(
      settings: settings,
      allowsControlCUnlock: allowsControlCUnlock,
      at: Date()
    )
    guard outcome == .acquired else {
      teardownEventTap()
      return outcome
    }
    markLocked()
    return outcome
  }

  /// Updates the active settings. If a lock is running, changes take effect immediately
  /// (e.g. a new auto-unlock timeout re-arms the timer); otherwise they seed the next lock.
  public func updateSettings(_ settings: KeyboardLockerSettings) {
    runtimeState.updateSettings(settings)

    if runtimeState.isLocked {
      configureAutoUnlockTimerIfNeeded()
    }
  }

  private func startEventTap() throws {
    let installation: EventTapInstallation<CFMachPort, CFRunLoopSource>
    do {
      installation = try EventTapInstallation.make(
        createTap: {
          CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMasks,
            callback: eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
          )
        },
        createSource: {
          CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            $0,
            Self.runLoopSourceOrder
          )
        },
        attachSource: {
          CFRunLoopAddSource(CFRunLoopGetMain(), $0, .commonModes)
        },
        enableTap: {
          CGEvent.tapEnable(tap: $0, enable: true)
        },
        isTapEnabled: {
          CGEvent.tapIsEnabled(tap: $0)
        },
        detachSource: {
          CFRunLoopRemoveSource(CFRunLoopGetMain(), $0, .commonModes)
        },
        invalidateTap: CFMachPortInvalidate
      )
    } catch EventTapInstallationError.eventTapCreationFailed {
      throw LockEngineError.eventTapCreationFailed
    } catch EventTapInstallationError.runLoopSourceCreationFailed {
      throw LockEngineError.runLoopSourceCreationFailed
    } catch EventTapInstallationError.eventTapEnableFailed {
      throw LockEngineError.eventTapEnableFailed
    }

    eventTapGeneration &+= 1
    eventTap = installation.tap
    runLoopSource = installation.source
  }

  private func markLocked() {
    configureAutoUnlockTimerIfNeeded()
    LockStateBroadcaster.broadcast()
    Self.logger.info("Locked")
  }

  private func configureAutoUnlockTimerIfNeeded() {
    cancelAutoUnlockTimer()

    let timeout = runtimeState.activeSettings.autoUnlockPolicy.timeout

    // An explicit settings update starts a fresh timeout window without changing when the
    // authoritative lock began. A duplicate lock request never reaches this path.
    let referenceDate = Date()
    guard
      runtimeState.isLocked,
      let schedule = AutoUnlockSchedule.make(
        timeout: timeout,
        referenceDate: referenceDate,
        currentDate: Date()
      )
    else {
      return
    }

    runtimeState.setAutoUnlockTargetDate(schedule.deadline)

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
    runtimeState.setAutoUnlockTargetDate(nil)
  }

  public func unlock() {
    guard runtimeState.isLocked else {
      return
    }

    cancelAutoUnlockTimer()
    teardownEventTap()
    resetLockState()
  }

  private func teardownEventTap() {
    let tap = eventTap
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }

    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      runLoopSource = nil
    }

    if let tap {
      CFMachPortInvalidate(tap)
      eventTap = nil
    }
  }

  private func resetLockState() {
    runtimeState.end()

    LockStateBroadcaster.broadcast()
    Self.logger.info("Unlocked")
  }

  fileprivate func handleDisabledEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    guard runtimeState.isLocked, let tap = eventTap else {
      return Unmanaged.passUnretained(event)
    }

    Self.logger.warning("Event tap disabled by system, attempting to re-enable")
    CGEvent.tapEnable(tap: tap, enable: true)

    guard !CGEvent.tapIsEnabled(tap: tap) else {
      return Unmanaged.passUnretained(event)
    }

    let failedGeneration = eventTapGeneration
    Self.logger.error("Event tap could not be re-enabled; transitioning to unlocked")
    DispatchQueue.main.async { [weak self] in
      self?.handleEventTapFailure(generation: failedGeneration)
    }
    return Unmanaged.passUnretained(event)
  }

  private func handleEventTapFailure(generation: UInt64) {
    guard runtimeState.isLocked, eventTapGeneration == generation else {
      return
    }

    cancelAutoUnlockTimer()
    teardownEventTap()
    resetLockState()
  }

  fileprivate func handleEvent(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    guard runtimeState.isLocked else {
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
    UnlockGestureMatcher.matches(
      type: type,
      keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
      flags: event.flags,
      isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat)
        == Self.autoRepeatFlagValue,
      configuredHotkey: runtimeState.activeSettings.unlockHotkey,
      allowsControlCUnlock: runtimeState.allowsControlCUnlock
    )
  }

  func lockDuration(at date: Date = Date()) -> TimeInterval? {
    guard let start = runtimeState.startedAt else {
      return nil
    }
    return max(0, date.timeIntervalSince(start))
  }

  func remainingAutoUnlockTime(at date: Date = Date()) -> TimeInterval? {
    guard let deadline = runtimeState.autoUnlockTargetDate else {
      return nil
    }
    return max(0, deadline.timeIntervalSince(date))
  }
}
