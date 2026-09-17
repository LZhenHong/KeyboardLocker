import AppKit
import Carbon
import Common
@preconcurrency import CoreGraphics
import Foundation
import IOKit
import os

struct AutoUnlockSchedule: Equatable {
  let deadline: Date
  let delay: TimeInterval

  static func make(
    timeout: TimeInterval?,
    referenceDate: Date,
    currentDate: Date
  ) -> Self? {
    guard let timeout,
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

enum LockRequestSource {
  case focusFilter
  case general
}

struct LockRuntimeState: Equatable {
  private(set) var activeSettings: KeyboardLockerSettings = .default
  private(set) var allowsControlCUnlock = false
  private(set) var autoUnlockTargetDate: Date?
  private(set) var focusOwnedLockGeneration: UInt64?
  private(set) var isLocked = false
  private(set) var lastUnlock: UnlockRecord?
  private(set) var lockGeneration: UInt64?
  private(set) var startedAt: Date?

  private var nextLockGeneration: UInt64 = 0

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
    focusOwnedLockGeneration = nil
    isLocked = true
    nextLockGeneration &+= 1
    lockGeneration = nextLockGeneration
    startedAt = date
    return .acquired
  }

  mutating func markCurrentLockAsFocusOwned() {
    focusOwnedLockGeneration = lockGeneration
  }

  /// Handles a request that arrives while the physical lock already exists. Focus observes an
  /// existing lock without claiming it; an explicit general request takes persistence over from
  /// a Focus-created generation without changing the physical runtime state.
  mutating func handleDuplicateLockRequest(
    from source: LockRequestSource
  ) -> LockRequestOutcome? {
    guard isLocked else {
      return nil
    }

    if source == .general {
      takeOverFocusOwnedLock()
    }
    return .alreadyLocked
  }

  /// Converts a Focus-created lock into an ordinary global desired lock without changing any
  /// physical runtime state. A later Focus deactivation must no longer release it.
  mutating func takeOverFocusOwnedLock() {
    focusOwnedLockGeneration = nil
  }

  /// The generation to release on Focus deactivation, or nil. The `== lockGeneration` identity
  /// check is the reason ownership is a generation and not a bool: a late Focus-off event may
  /// arrive after arbitrary unlock/relock cycles, and it must release only the exact lock Focus
  /// created — never a newer, unrelated global lock.
  var focusOwnedGenerationForRelease: UInt64? {
    guard isLocked,
          focusOwnedLockGeneration == lockGeneration
    else {
      return nil
    }
    return focusOwnedLockGeneration
  }

  func matchesCurrentLockGeneration(_ generation: UInt64) -> Bool {
    isLocked && lockGeneration == generation
  }

  mutating func updateSettings(_ settings: KeyboardLockerSettings) {
    activeSettings = settings
  }

  mutating func setAutoUnlockTargetDate(_ date: Date?) {
    autoUnlockTargetDate = date
  }

  /// Every unlock path funnels through here so the record always pairs the real reason with the
  /// Agent's own clock. The record survives a later `begin` on purpose: a running lock may still
  /// report how the previous one ended.
  mutating func end(reason: UnlockRecord.Reason, at date: Date) {
    allowsControlCUnlock = false
    autoUnlockTargetDate = nil
    focusOwnedLockGeneration = nil
    isLocked = false
    lockGeneration = nil
    startedAt = nil
    lastUnlock = UnlockRecord(reason: reason, date: date)
  }

  func statusSnapshot(capturedAt: Date) -> LockStatusSnapshot {
    LockStatusSnapshot(
      capturedAt: capturedAt,
      isLocked: isLocked,
      startedAt: startedAt,
      autoUnlockTargetDate: autoUnlockTargetDate,
      settings: activeSettings,
      lastUnlock: lastUnlock
    )
  }
}

enum UnlockGestureMatcher {
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

/// Rolling suffix matcher for the type-to-unlock phrase of one lock generation.
///
/// The buffer never grows past the phrase length and is never logged, persisted, or carried
/// into a snapshot: it exists only so a deliberate typed phrase can end the lock while every
/// keystroke is being consumed. Ingest exactly the characters admitted by
/// `KeyboardLockerSettings.isAllowedInUnlockPhrase`, lowercased.
struct UnlockPhraseMatcher: Equatable {
  private let phrase: [Character]
  private var buffer: [Character] = []

  init(phrase: String) {
    self.phrase = Array(phrase)
  }

  mutating func ingest(_ character: Character) {
    buffer.append(character)
    if buffer.count > phrase.count {
      buffer.removeFirst()
    }
  }

  mutating func backspace() {
    if !buffer.isEmpty {
      buffer.removeLast()
    }
  }

  mutating func reset() {
    buffer.removeAll()
  }

  var matched: Bool {
    buffer == phrase
  }
}

/// System-defined events share a channel with auxiliary mouse buttons. Classify them explicitly so
/// keyboard controls are consumed without broadening the lock to pointer input.
enum LockedKeyboardEventPolicy {
  static let systemDefinedEventType: CGEventType = {
    guard let type = CGEventType(rawValue: UInt32(NX_SYSDEFINED)) else {
      preconditionFailure("NX_SYSDEFINED must map to a CGEventType")
    }
    return type
  }()

  private static let suppressibleSystemDefinedSubtypes: Set<Int16> = [
    Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
    Int16(NX_SUBTYPE_EJECT_KEY),
    Int16(NX_SUBTYPE_POWER_KEY),
  ]

  static func shouldSuppress(
    type: CGEventType,
    systemDefinedSubtype: Int16? = nil
  ) -> Bool {
    switch type {
    case .flagsChanged, .keyDown, .keyUp:
      return true

    case systemDefinedEventType:
      guard let systemDefinedSubtype else {
        return false
      }
      return suppressibleSystemDefinedSubtypes.contains(systemDefinedSubtype)

    default:
      return false
    }
  }

  static func shouldSuppress(type: CGEventType, event: CGEvent) -> Bool {
    let systemDefinedSubtype = type == systemDefinedEventType
      ? NSEvent(cgEvent: event)?.subtype.rawValue
      : nil
    return shouldSuppress(type: type, systemDefinedSubtype: systemDefinedSubtype)
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

/// The installed-tap operations `LockEngine` relies on. The live implementation wraps the real
/// `CFMachPort` tap and its run-loop source; tests substitute a fake to drive the tap-disable
/// and teardown paths deterministically.
protocol InstalledEventTap: AnyObject {
  var isEnabled: Bool { get }
  func setEnabled(_ enabled: Bool)
  /// Disables the tap, detaches its run-loop source, and invalidates the port.
  func teardown()
}

/// Every side effect `LockEngine` performs on the outside world, injected so `ServiceTests`
/// can drive the engine without Quartz, TCC, real timers, or system notifications.
struct LockEngineDependencies {
  var hasAccessibilityPermission: @MainActor () -> Bool
  var installEventTap: @MainActor (LockEngine) throws -> any InstalledEventTap
  var scheduleTimer: MainActorTimerScheduler
  /// Maps a key press to the character it types on the current layout (shift-aware), for the
  /// unlock-phrase matcher. Injected so tests drive phrase matching without the TIS layout.
  var characterForKeyCode: @MainActor (CGKeyCode, Bool) -> Character?
  /// Registers a main-actor observer fired once per system wake and returns its cancellation.
  /// The auto-unlock timer runs on the monotonic clock and pauses during sleep, while the
  /// published deadline is wall-clock — this signal is what lets the engine reconcile them.
  var observeSystemWake: @MainActor (
    @escaping @MainActor @Sendable () -> Void
  ) -> @MainActor () -> Void
  var broadcastStateChange: () -> Void
  var now: () -> Date

  @MainActor static var live: Self {
    Self(
      hasAccessibilityPermission: { AccessibilityManager.hasPermission() },
      installEventTap: { engine in try CoreGraphicsEventTap.install(engine: engine) },
      scheduleTimer: liveMainActorTimerScheduler,
      characterForKeyCode: { keyCode, shiftDown in
        KeyCodeConverter.typedCharacter(for: keyCode, shiftDown: shiftDown)
      },
      observeSystemWake: { handler in
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(
          forName: NSWorkspace.didWakeNotification,
          object: nil,
          queue: .main
        ) { _ in
          MainActor.assumeIsolated { handler() }
        }
        return { center.removeObserver(observer) }
      },
      broadcastStateChange: { LockStateBroadcaster.broadcast() },
      now: { Date() }
    )
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

/// Live `InstalledEventTap` backed by a Quartz session event tap on the main run loop.
private final class CoreGraphicsEventTap: InstalledEventTap {
  private static let runLoopSourceOrder: CFIndex = 0

  private let tap: CFMachPort
  private let source: CFRunLoopSource

  private init(installation: EventTapInstallation<CFMachPort, CFRunLoopSource>) {
    tap = installation.tap
    source = installation.source
  }

  var isEnabled: Bool {
    CGEvent.tapIsEnabled(tap: tap)
  }

  func setEnabled(_ enabled: Bool) {
    CGEvent.tapEnable(tap: tap, enable: enabled)
  }

  func teardown() {
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    CFMachPortInvalidate(tap)
  }

  /// Acquires the tap and its run-loop source as one transaction, surfacing engine errors.
  static func install(engine: LockEngine) throws -> CoreGraphicsEventTap {
    let installation: EventTapInstallation<CFMachPort, CFRunLoopSource>
    do {
      installation = try EventTapInstallation.make(
        createTap: {
          CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: LockEngine.eventMasks,
            callback: eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(engine).toOpaque())
          )
        },
        createSource: {
          CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            $0,
            runLoopSourceOrder
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
      throw LockEngine.LockEngineError.eventTapCreationFailed
    } catch EventTapInstallationError.runLoopSourceCreationFailed {
      throw LockEngine.LockEngineError.runLoopSourceCreationFailed
    } catch EventTapInstallationError.eventTapEnableFailed {
      throw LockEngine.LockEngineError.eventTapEnableFailed
    }

    return CoreGraphicsEventTap(installation: installation)
  }
}

@MainActor
final class LockEngine {
  static let logger = Logger(subsystem: SharedConstants.machServiceName, category: "LockEngine")

  enum LockEngineError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case eventTapCreationFailed
    case eventTapEnableFailed
    case runLoopSourceCreationFailed

    var errorDescription: String? {
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

    var recoverySuggestion: String? {
      switch self {
      case .accessibilityPermissionDenied:
        "Open System Settings → Privacy & Security → Accessibility and enable access for the KeyboardLocker agent."
      case .eventTapCreationFailed:
        "Try restarting KeyboardLocker. If the problem persists, check Accessibility permissions for the KeyboardLocker agent in System Settings → Privacy & Security → Accessibility."
      case .eventTapEnableFailed:
        "Check Accessibility permissions for the KeyboardLocker agent in System Settings → Privacy & Security → Accessibility, then try locking again."
      case .runLoopSourceCreationFailed:
        "This is a system-level error. Please contact support if it persists."
      }
    }
  }

  /// Suppress standard keys and keyboard-originated system controls without observing pointer input.
  nonisolated static let eventMasks: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue) |
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << LockedKeyboardEventPolicy.systemDefinedEventType.rawValue)

  private static let autoRepeatFlagValue: Int64 = 1

  /// Minimum interval between blocked-input nudges. Enforced here, at the input boundary, so a
  /// held key cannot flood the notification centers and subscribers can stay trivial.
  private static let blockedInputReportThrottle: TimeInterval = 4

  private let dependencies: LockEngineDependencies
  private var installedTap: (any InstalledEventTap)?
  private var eventTapGeneration: UInt64 = 0
  private var cancelScheduledAutoUnlock: (() -> Void)?
  private var cancelWakeObservation: (() -> Void)?
  /// Rolling phrase matcher owned by the current lock generation; nil while unlocked or when
  /// the lock's settings disable the gesture. Never logged or exposed.
  private var phraseMatcher: UnlockPhraseMatcher?
  private var runtimeState = LockRuntimeState()
  private var stateChangeHandler: () -> Void = {}
  private var blockedInputHandler: () -> Void = {}
  private var lastBlockedInputReportAt: Date?

  var isLocked: Bool {
    runtimeState.isLocked
  }

  /// One coherent Agent-owned snapshot for read-only wrappers and presentation surfaces.
  var statusSnapshot: LockStatusSnapshot {
    runtimeState.statusSnapshot(capturedAt: dependencies.now())
  }

  init(dependencies: LockEngineDependencies) {
    self.dependencies = dependencies
    cancelWakeObservation = dependencies.observeSystemWake { [weak self] in
      self?.reconcileAutoUnlockAfterWake()
    }
  }

  /// Wires Agent-owned presentation after both the engine and its observer exist. The production
  /// composition root installs exactly one handler before exposing the XPC listener.
  func setStateChangeHandler(_ handler: @escaping () -> Void) {
    stateChangeHandler = handler
  }

  /// Installs the blocked-input nudge. Fired (already settings-gated and throttled) when the
  /// lock swallows a keystroke that is not an unlock gesture, so a presentation surface can
  /// explain why typing has no effect.
  func setBlockedInputHandler(_ handler: @escaping () -> Void) {
    blockedInputHandler = handler
  }

  @discardableResult
  func lock(
    settings: KeyboardLockerSettings = .default,
    allowsControlCUnlock: Bool = false
  ) throws -> LockRequestOutcome {
    try acquireLock(
      settings: settings,
      allowsControlCUnlock: allowsControlCUnlock,
      source: .general
    )
  }

  /// Applies the Focus Filter's desired state without giving Focus ownership of a pre-existing
  /// global lock. Deactivation releases only the exact lock generation created by Focus.
  func setFocusFilterLockEnabled(
    _ enabled: Bool,
    settings: KeyboardLockerSettings = .default
  ) throws {
    if enabled {
      _ = try acquireLock(
        settings: settings,
        allowsControlCUnlock: false,
        source: .focusFilter
      )
    } else if let generation = runtimeState.focusOwnedGenerationForRelease {
      unlock(ifLockGeneration: generation, reason: .focusFilter)
    }
  }

  private func acquireLock(
    settings: KeyboardLockerSettings,
    allowsControlCUnlock: Bool,
    source: LockRequestSource
  ) throws -> LockRequestOutcome {
    // A duplicate never mutates the physical lock, its settings, gestures, start time, or
    // deadline. An explicit non-Focus desired-lock does take over persistence from Focus so a
    // later Focus deactivation cannot undo the user's newer intent.
    if let duplicateOutcome = runtimeState.handleDuplicateLockRequest(from: source) {
      return duplicateOutcome
    }

    // Verify Accessibility permission before attempting to create event tap.
    guard dependencies.hasAccessibilityPermission() else {
      throw LockEngineError.accessibilityPermissionDenied
    }

    // Event tap creation must happen on main thread
    try startEventTap()
    let outcome = runtimeState.begin(
      settings: settings,
      allowsControlCUnlock: allowsControlCUnlock,
      at: dependencies.now()
    )
    guard outcome == .acquired else {
      teardownEventTap()
      return outcome
    }
    // The matcher belongs to this lock generation: its buffer starts empty and its phrase is
    // the one the lock began with, so a duplicate request cannot change a running lock's
    // gesture.
    phraseMatcher = settings.unlockPhrase.map { UnlockPhraseMatcher(phrase: $0) }
    if source == .focusFilter {
      runtimeState.markCurrentLockAsFocusOwned()
    }
    markLocked()
    return outcome
  }

  /// Updates the active settings. If a lock is running, changes take effect immediately
  /// (e.g. a new auto-unlock timeout re-arms the timer); otherwise they seed the next lock.
  func updateSettings(_ settings: KeyboardLockerSettings) {
    runtimeState.updateSettings(settings)
    // An explicit settings update also re-arms the phrase gesture; any partial input belongs
    // to the previous configuration.
    phraseMatcher = settings.unlockPhrase.map { UnlockPhraseMatcher(phrase: $0) }

    if runtimeState.isLocked {
      configureAutoUnlockTimerIfNeeded()
    }
  }

  private func startEventTap() throws {
    installedTap = try dependencies.installEventTap(self)
    eventTapGeneration &+= 1
  }

  private func markLocked() {
    configureAutoUnlockTimerIfNeeded()
    // A new lock generation re-arms the feedback nudge: the first swallowed keystroke of this
    // lock should surface immediately, not inherit the previous lock's throttle window.
    lastBlockedInputReportAt = nil
    publishStateChange()
    Self.logger.info("Locked")
  }

  private func configureAutoUnlockTimerIfNeeded() {
    cancelAutoUnlockTimer()

    let timeout = runtimeState.activeSettings.autoUnlockPolicy.timeout

    // An explicit settings update starts a fresh timeout window without changing when the
    // authoritative lock began. A duplicate lock request never reaches this path.
    let referenceDate = dependencies.now()
    guard runtimeState.isLocked,
          let schedule = AutoUnlockSchedule.make(
            timeout: timeout,
            referenceDate: referenceDate,
            currentDate: dependencies.now()
          )
    else {
      return
    }

    runtimeState.setAutoUnlockTargetDate(schedule.deadline)

    guard let lockGeneration = runtimeState.lockGeneration else {
      return
    }

    cancelScheduledAutoUnlock = dependencies.scheduleTimer(schedule.delay) { [weak self] in
      self?.unlock(ifLockGeneration: lockGeneration, reason: .autoUnlock)
    }
  }

  /// The auto-unlock timer runs on the monotonic clock, which pauses while the system sleeps,
  /// but `autoUnlockTargetDate` is published wall-clock. Reconcile the two on wake: expire
  /// immediately when the deadline passed during sleep, otherwise re-arm for the remaining
  /// wall-clock interval so the lock still ends at the advertised time instead of drifting by
  /// the sleep duration.
  private func reconcileAutoUnlockAfterWake() {
    guard runtimeState.isLocked,
          let deadline = runtimeState.autoUnlockTargetDate,
          let lockGeneration = runtimeState.lockGeneration
    else {
      return
    }

    let remaining = deadline.timeIntervalSince(dependencies.now())
    guard remaining > 0 else {
      unlock(ifLockGeneration: lockGeneration, reason: .autoUnlock)
      return
    }

    // Cancel only the pending fire — the published deadline must not be rewritten by a
    // sleep/wake cycle, so this path deliberately does not go through `cancelAutoUnlockTimer`.
    cancelScheduledAutoUnlock?()
    cancelScheduledAutoUnlock = dependencies.scheduleTimer(remaining) { [weak self] in
      self?.unlock(ifLockGeneration: lockGeneration, reason: .autoUnlock)
    }
  }

  private func cancelAutoUnlockTimer() {
    cancelScheduledAutoUnlock?()
    cancelScheduledAutoUnlock = nil
    runtimeState.setAutoUnlockTargetDate(nil)
  }

  func unlock() {
    endActiveLock(reason: .explicit, fencedTo: nil)
  }

  private func unlock(ifLockGeneration generation: UInt64, reason: UnlockRecord.Reason) {
    endActiveLock(reason: reason, fencedTo: generation)
  }

  /// Shared teardown for every unlock path. The fence rejects stale timers, gestures, and Focus
  /// releases that arrive after a newer lock generation began.
  private func endActiveLock(reason: UnlockRecord.Reason, fencedTo generation: UInt64?) {
    if let generation {
      guard runtimeState.matchesCurrentLockGeneration(generation) else {
        return
      }
    }
    guard runtimeState.isLocked else {
      return
    }

    cancelAutoUnlockTimer()
    teardownEventTap()
    resetLockState(reason: reason)
  }

  private func teardownEventTap() {
    installedTap?.teardown()
    installedTap = nil
  }

  private func resetLockState(reason: UnlockRecord.Reason) {
    runtimeState.end(reason: reason, at: dependencies.now())
    // No keystroke residue may survive the lock that collected it.
    phraseMatcher = nil

    publishStateChange()
    Self.logger.info("Unlocked")
  }

  private func publishStateChange() {
    dependencies.broadcastStateChange()
    stateChangeHandler()
  }

  func handleDisabledEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    guard runtimeState.isLocked, let tap = installedTap else {
      return Unmanaged.passUnretained(event)
    }

    Self.logger.warning("Event tap disabled by system, attempting to re-enable")
    tap.setEnabled(true)

    guard !tap.isEnabled else {
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
    resetLockState(reason: .eventTapFailure)
  }

  func handleEvent(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    guard runtimeState.isLocked else {
      return Unmanaged.passUnretained(event)
    }

    guard LockedKeyboardEventPolicy.shouldSuppress(type: type, event: event) else {
      return Unmanaged.passUnretained(event)
    }

    if shouldTriggerUnlock(for: type, event: event) {
      unlockFromInputGesture(.gesture)
    } else if shouldUnlockViaPhrase(type: type, event: event) {
      unlockFromInputGesture(.phrase)
    } else {
      reportBlockedInput(type: type)
    }

    return nil
  }

  /// Nudges presentation surfaces when the lock swallows a key press that is not an unlock
  /// gesture. Only key-downs and keyboard system controls report: key-ups and flags-changed
  /// carry no "typing" intent, and counting them would fire the nudge on the release of the
  /// unlock hotkey itself. Throttled per lock generation and gated by the active settings.
  private func reportBlockedInput(type: CGEventType) {
    guard type == .keyDown || type == LockedKeyboardEventPolicy.systemDefinedEventType else {
      return
    }
    guard runtimeState.activeSettings.blockedInputFeedbackEnabled else {
      return
    }

    let now = dependencies.now()
    if let lastReport = lastBlockedInputReportAt,
       now.timeIntervalSince(lastReport) < Self.blockedInputReportThrottle {
      return
    }
    lastBlockedInputReportAt = now
    blockedInputHandler()
  }

  /// Input-gesture unlocks dispatch through the main queue so the tap callback stays
  /// non-blocking; the generation fence rejects a gesture that raced a newer lock.
  private func unlockFromInputGesture(_ reason: UnlockRecord.Reason) {
    let lockGeneration = runtimeState.lockGeneration
    DispatchQueue.main.async { [weak self] in
      guard let lockGeneration else {
        return
      }
      self?.unlock(ifLockGeneration: lockGeneration, reason: reason)
    }
  }

  /// Feeds the rolling phrase matcher. Only plain character key-downs count: modifier chords
  /// and non-character keys reset the buffer, backspace edits it, and auto-repeat is ignored
  /// so a held key neither completes nor breaks a phrase.
  private func shouldUnlockViaPhrase(type: CGEventType, event: CGEvent) -> Bool {
    guard runtimeState.isLocked, phraseMatcher != nil, type == .keyDown else {
      return false
    }
    guard event.getIntegerValueField(.keyboardEventAutorepeat) != Self.autoRepeatFlagValue else {
      return false
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    // Command/control/option chords are gestures, not phrase input; one breaks the sequence.
    guard flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else {
      phraseMatcher?.reset()
      return false
    }

    if keyCode == CGKeyCode(kVK_Delete) {
      phraseMatcher?.backspace()
      return false
    }

    guard let character = dependencies.characterForKeyCode(
      keyCode,
      flags.contains(.maskShift)
    ) else {
      phraseMatcher?.reset()
      return false
    }
    let lowered = Character(character.lowercased())
    guard KeyboardLockerSettings.isAllowedInUnlockPhrase(lowered) else {
      phraseMatcher?.reset()
      return false
    }

    phraseMatcher?.ingest(lowered)
    return phraseMatcher?.matched == true
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
}
