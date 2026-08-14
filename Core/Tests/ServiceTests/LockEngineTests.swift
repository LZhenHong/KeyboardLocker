import Common
import CoreGraphics
import Foundation
@testable import Service
import Testing

@MainActor
@Suite(.serialized)
final class LockEngineTests {
  private let tap: FakeInstalledEventTap
  private let scheduler: ManualTimerScheduler
  private var installCount: Int
  private var broadcastCount: Int
  private var stateChangeCount: Int
  private var hasAccessibilityPermission: Bool
  private let now: Date

  init() {
    tap = FakeInstalledEventTap()
    scheduler = ManualTimerScheduler()
    installCount = 0
    broadcastCount = 0
    stateChangeCount = 0
    hasAccessibilityPermission = true
    now = Date(timeIntervalSinceReferenceDate: 1000)
  }

  // MARK: - Acquisition

  @Test
  func lockWithoutAccessibilityPermissionThrowsBeforeInstallingTap() {
    hasAccessibilityPermission = false
    let engine = makeEngine()

    #expect(throws: LockEngine.LockEngineError.accessibilityPermissionDenied) {
      try engine.lock(settings: makeSettings())
    }
    #expect(installCount == 0)
    #expect(!engine.isLocked)
    #expect(broadcastCount == 0)
  }

  @Test
  func lockInstallsTapSchedulesAutoUnlockAndBroadcasts() throws {
    let engine = makeEngine()

    let outcome = try engine.lock(settings: makeSettings())

    #expect(outcome == .acquired)
    #expect(engine.isLocked)
    #expect(installCount == 1)
    #expect(broadcastCount == 1)
    #expect(scheduler.timers.map(\.interval) == [60])
    #expect(engine.statusSnapshot.autoUnlockTargetDate == now.addingTimeInterval(60))
  }

  @Test
  func duplicateLockNeverMutatesTheRunningLock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    let duplicate = try engine.lock(
      settings: makeSettings(autoUnlockPolicy: .timed(seconds: 120))
    )

    #expect(duplicate == .alreadyLocked)
    #expect(installCount == 1)
    #expect(scheduler.timers.count == 1)
    #expect(broadcastCount == 1)
    #expect(engine.statusSnapshot.autoUnlockTargetDate == now.addingTimeInterval(60))
  }

  // MARK: - Auto-unlock scheduling

  @Test
  func autoUnlockTimerFireUnlocks() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    scheduler.timers[0].fire()

    #expect(!engine.isLocked)
    #expect(tap.teardownCallCount == 1)
    #expect(broadcastCount == 2)
    #expect(engine.statusSnapshot.autoUnlockTargetDate == nil)
  }

  @Test
  func staleTimerFireKeepsNewerLock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())
    let staleTimer = scheduler.timers[0]

    engine.unlock()
    #expect(staleTimer.isCancelled)

    _ = try engine.lock(settings: makeSettings())
    #expect(scheduler.timers.count == 2)

    // A cancel that lost the race against an already-queued fire must not unlock the new lock.
    staleTimer.fire()
    #expect(engine.isLocked)
  }

  @Test
  func updateSettingsWhileLockedRearmsAutoUnlock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    engine.updateSettings(makeSettings(autoUnlockPolicy: .timed(seconds: 120)))

    #expect(scheduler.timers.map(\.interval) == [60, 120])
    #expect(scheduler.timers[0].isCancelled)
    #expect(!scheduler.timers[1].isCancelled)
    #expect(engine.statusSnapshot.autoUnlockTargetDate == now.addingTimeInterval(120))
  }

  @Test
  func updateSettingsWhileUnlockedSchedulesNoTimer() {
    let engine = makeEngine()

    engine.updateSettings(makeSettings())

    #expect(scheduler.timers.isEmpty)
    #expect(engine.statusSnapshot.autoUnlockTargetDate == nil)
  }

  @Test
  func lockWithDisabledAutoUnlockSchedulesNoTimer() throws {
    let engine = makeEngine()

    _ = try engine.lock(settings: makeSettings(autoUnlockPolicy: .disabled))

    #expect(engine.isLocked)
    #expect(scheduler.timers.isEmpty)
    #expect(engine.statusSnapshot.autoUnlockTargetDate == nil)
  }

  // MARK: - Unlock gestures

  @Test
  func unlockHotkeyEventUnlocksAfterDispatch() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    let event = makeKeyEvent(keyCode: 4, flags: .maskShift)
    #expect(engine.handleEvent(type: .keyDown, event: event) == nil)
    #expect(engine.isLocked)

    await flushMainQueue()

    #expect(!engine.isLocked)
    #expect(tap.teardownCallCount == 1)
    #expect(broadcastCount == 2)
  }

  @Test
  func unrelatedKeyEventIsConsumedWithoutUnlocking() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    let event = makeKeyEvent(keyCode: 40)
    #expect(engine.handleEvent(type: .keyDown, event: event) == nil)

    await flushMainQueue()

    #expect(engine.isLocked)
    #expect(tap.teardownCallCount == 0)
  }

  @Test
  func controlCUnlocksOnlyWhenAllowed() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(), allowsControlCUnlock: false)

    let controlC = makeKeyEvent(
      keyCode: UnlockGestureMatcher.controlCKeyCode,
      flags: .maskControl
    )
    #expect(engine.handleEvent(type: .keyDown, event: controlC) == nil)
    await flushMainQueue()
    #expect(engine.isLocked)

    engine.unlock()
    _ = try engine.lock(settings: makeSettings(), allowsControlCUnlock: true)
    #expect(engine.handleEvent(type: .keyDown, event: controlC) == nil)
    await flushMainQueue()
    #expect(!engine.isLocked)
  }

  // MARK: - Event tap failure

  @Test
  func tapDisabledAndReenabledKeepsLock() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    tap.isEnabled = false
    let event = makeKeyEvent(keyCode: 0)
    #expect(engine.handleDisabledEvent(event) != nil)

    await flushMainQueue()

    #expect(engine.isLocked)
    #expect(tap.setEnabledCalls == [true])
    #expect(tap.teardownCallCount == 0)
    #expect(broadcastCount == 1)
  }

  @Test
  func tapDisabledBeyondRecoveryUnlocksFailOpen() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    tap.isEnabled = false
    tap.allowsReEnable = false
    let event = makeKeyEvent(keyCode: 0)
    #expect(engine.handleDisabledEvent(event) != nil)
    #expect(engine.isLocked)

    await flushMainQueue()

    #expect(!engine.isLocked)
    #expect(tap.teardownCallCount == 1)
    #expect(broadcastCount == 2)
  }

  @Test
  func staleTapFailureKeepsNewerLock() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    tap.isEnabled = false
    tap.allowsReEnable = false
    let event = makeKeyEvent(keyCode: 0)
    #expect(engine.handleDisabledEvent(event) != nil)

    engine.unlock()
    tap.isEnabled = true
    tap.allowsReEnable = true
    _ = try engine.lock(settings: makeSettings())

    await flushMainQueue()

    #expect(engine.isLocked)
  }

  // MARK: - Unlock

  @Test
  func unlockCancelsTimerTearsDownAndBroadcasts() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    engine.unlock()

    #expect(!engine.isLocked)
    #expect(scheduler.timers[0].isCancelled)
    #expect(tap.teardownCallCount == 1)
    #expect(broadcastCount == 2)
    #expect(engine.statusSnapshot.autoUnlockTargetDate == nil)
  }

  @Test
  func stateChangeHandlerFollowsCommittedLockTransitions() throws {
    let engine = makeEngine()

    _ = try engine.lock(settings: makeSettings())
    engine.unlock()

    #expect(stateChangeCount == 2)
  }

  // MARK: - Focus ownership

  @Test
  func focusDeactivationReleasesFocusOwnedLock() throws {
    let engine = makeEngine()
    try engine.setFocusFilterLockEnabled(true, settings: makeSettings())
    #expect(engine.isLocked)

    try engine.setFocusFilterLockEnabled(false, settings: makeSettings())

    #expect(!engine.isLocked)
    #expect(tap.teardownCallCount == 1)
  }

  @Test
  func focusDeactivationKeepsLockTakenOverByGeneralRequest() throws {
    let engine = makeEngine()
    try engine.setFocusFilterLockEnabled(true, settings: makeSettings())

    // An explicit lock takes persistence over from the Focus-created generation.
    let takeover = try engine.lock(settings: makeSettings())
    #expect(takeover == .alreadyLocked)

    try engine.setFocusFilterLockEnabled(false, settings: makeSettings())

    #expect(engine.isLocked)
    #expect(tap.teardownCallCount == 0)
  }

  // MARK: - Helpers

  private func makeEngine() -> LockEngine {
    let engine = LockEngine(dependencies: LockEngineDependencies(
      hasAccessibilityPermission: { self.hasAccessibilityPermission },
      installEventTap: { _ in
        self.installCount += 1
        return self.tap
      },
      scheduleTimer: scheduler.scheduler,
      broadcastStateChange: { self.broadcastCount += 1 },
      now: { self.now }
    ))
    engine.setStateChangeHandler { self.stateChangeCount += 1 }
    return engine
  }

  private func makeSettings(
    autoUnlockPolicy: KeyboardLockerSettings.AutoUnlockPolicy = .timed(seconds: 60)
  ) -> KeyboardLockerSettings {
    KeyboardLockerSettings(
      autoUnlockPolicy: autoUnlockPolicy,
      unlockHotkey: KeyboardLockerSettings.Hotkey(keyCode: 4, modifierFlags: .maskShift)
    )
  }

  private func makeKeyEvent(
    keyCode: CGKeyCode,
    flags: CGEventFlags = []
  ) -> CGEvent {
    // Fabrication only builds an in-memory event value; nothing is posted to the HID system.
    // Bind the result to a local when asserting on a handler's return: handlers hand the event
    // back unretained, so it must outlive the returned reference.
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    event.flags = flags
    return event
  }

  /// Runs the main-queue hop the engine uses to dispatch unlock and tap-failure work.
  private func flushMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }
}

private final class FakeInstalledEventTap: InstalledEventTap {
  var isEnabled = true
  var allowsReEnable = true
  private(set) var setEnabledCalls: [Bool] = []
  private(set) var teardownCallCount = 0

  func setEnabled(_ enabled: Bool) {
    setEnabledCalls.append(enabled)
    guard enabled else {
      isEnabled = false
      return
    }
    if allowsReEnable {
      isEnabled = true
    }
  }

  func teardown() {
    teardownCallCount += 1
    isEnabled = false
  }
}

/// Manual scheduler whose timers stay fireable after cancellation: a cancelled dispatch block
/// may already be in flight, and the engine's generation guard must reject exactly that stale
/// fire, so tests need to replay it.
@MainActor
private final class ManualTimerScheduler {
  final class Timer {
    let interval: TimeInterval
    private let fireAction: @MainActor @Sendable () -> Void
    private(set) var isCancelled = false

    init(interval: TimeInterval, fire: @escaping @MainActor @Sendable () -> Void) {
      self.interval = interval
      fireAction = fire
    }

    func cancel() {
      isCancelled = true
    }

    @MainActor
    func fire() {
      fireAction()
    }
  }

  private(set) var timers: [Timer] = []

  var scheduler: MainActorTimerScheduler {
    { interval, fire in
      let timer = Timer(interval: interval, fire: fire)
      self.timers.append(timer)
      return { timer.cancel() }
    }
  }
}
