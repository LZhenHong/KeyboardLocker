import Common
import CoreGraphics
@testable import Service
import XCTest

@MainActor
final class LockEngineTests: XCTestCase {
  private var tap: FakeInstalledEventTap!
  private var scheduler: ManualTimerScheduler!
  private var installCount = 0
  private var broadcastCount = 0
  private var hasAccessibilityPermission = true
  private var now: Date!

  override func setUp() {
    super.setUp()
    tap = FakeInstalledEventTap()
    scheduler = ManualTimerScheduler()
    installCount = 0
    broadcastCount = 0
    hasAccessibilityPermission = true
    now = Date(timeIntervalSinceReferenceDate: 1_000)
  }

  // MARK: - Acquisition

  func testLockWithoutAccessibilityPermissionThrowsBeforeInstallingTap() {
    hasAccessibilityPermission = false
    let engine = makeEngine()

    XCTAssertThrowsError(try engine.lock(settings: makeSettings())) { error in
      XCTAssertEqual(error as? LockEngine.LockEngineError, .accessibilityPermissionDenied)
    }
    XCTAssertEqual(installCount, 0)
    XCTAssertFalse(engine.isLocked)
    XCTAssertEqual(broadcastCount, 0)
  }

  func testLockInstallsTapSchedulesAutoUnlockAndBroadcasts() throws {
    let engine = makeEngine()

    let outcome = try engine.lock(settings: makeSettings())

    XCTAssertEqual(outcome, .acquired)
    XCTAssertTrue(engine.isLocked)
    XCTAssertEqual(installCount, 1)
    XCTAssertEqual(broadcastCount, 1)
    XCTAssertEqual(scheduler.timers.map(\.interval), [60])
    XCTAssertEqual(
      engine.statusSnapshot.autoUnlockTargetDate,
      now.addingTimeInterval(60)
    )
  }

  func testDuplicateLockNeverMutatesTheRunningLock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    let duplicate = try engine.lock(
      settings: makeSettings(autoUnlockPolicy: .timed(seconds: 120))
    )

    XCTAssertEqual(duplicate, .alreadyLocked)
    XCTAssertEqual(installCount, 1)
    XCTAssertEqual(scheduler.timers.count, 1)
    XCTAssertEqual(broadcastCount, 1)
    XCTAssertEqual(
      engine.statusSnapshot.autoUnlockTargetDate,
      now.addingTimeInterval(60)
    )
  }

  // MARK: - Auto-unlock scheduling

  func testAutoUnlockTimerFireUnlocks() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    scheduler.timers[0].fire()

    XCTAssertFalse(engine.isLocked)
    XCTAssertEqual(tap.teardownCallCount, 1)
    XCTAssertEqual(broadcastCount, 2)
    XCTAssertNil(engine.statusSnapshot.autoUnlockTargetDate)
  }

  func testStaleTimerFireKeepsNewerLock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())
    let staleTimer = scheduler.timers[0]

    engine.unlock()
    XCTAssertTrue(staleTimer.isCancelled)

    _ = try engine.lock(settings: makeSettings())
    XCTAssertEqual(scheduler.timers.count, 2)

    // A cancel that lost the race against an already-queued fire must not unlock the new lock.
    staleTimer.fire()
    XCTAssertTrue(engine.isLocked)
  }

  func testUpdateSettingsWhileLockedRearmsAutoUnlock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    engine.updateSettings(makeSettings(autoUnlockPolicy: .timed(seconds: 120)))

    XCTAssertEqual(scheduler.timers.map(\.interval), [60, 120])
    XCTAssertTrue(scheduler.timers[0].isCancelled)
    XCTAssertFalse(scheduler.timers[1].isCancelled)
    XCTAssertEqual(
      engine.statusSnapshot.autoUnlockTargetDate,
      now.addingTimeInterval(120)
    )
  }

  func testUpdateSettingsWhileUnlockedSchedulesNoTimer() {
    let engine = makeEngine()

    engine.updateSettings(makeSettings())

    XCTAssertTrue(scheduler.timers.isEmpty)
    XCTAssertNil(engine.statusSnapshot.autoUnlockTargetDate)
  }

  func testLockWithDisabledAutoUnlockSchedulesNoTimer() throws {
    let engine = makeEngine()

    _ = try engine.lock(settings: makeSettings(autoUnlockPolicy: .disabled))

    XCTAssertTrue(engine.isLocked)
    XCTAssertTrue(scheduler.timers.isEmpty)
    XCTAssertNil(engine.statusSnapshot.autoUnlockTargetDate)
  }

  // MARK: - Unlock gestures

  func testUnlockHotkeyEventUnlocksAfterDispatch() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    let event = makeKeyEvent(keyCode: 4, flags: .maskShift)
    XCTAssertNil(engine.handleEvent(type: .keyDown, event: event))
    XCTAssertTrue(engine.isLocked)

    await flushMainQueue()

    XCTAssertFalse(engine.isLocked)
    XCTAssertEqual(tap.teardownCallCount, 1)
    XCTAssertEqual(broadcastCount, 2)
  }

  func testUnrelatedKeyEventIsConsumedWithoutUnlocking() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    let event = makeKeyEvent(keyCode: 40)
    XCTAssertNil(engine.handleEvent(type: .keyDown, event: event))

    await flushMainQueue()

    XCTAssertTrue(engine.isLocked)
    XCTAssertEqual(tap.teardownCallCount, 0)
  }

  func testControlCUnlocksOnlyWhenAllowed() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(), allowsControlCUnlock: false)

    let controlC = makeKeyEvent(
      keyCode: UnlockGestureMatcher.controlCKeyCode,
      flags: .maskControl
    )
    XCTAssertNil(engine.handleEvent(type: .keyDown, event: controlC))
    await flushMainQueue()
    XCTAssertTrue(engine.isLocked)

    engine.unlock()
    _ = try engine.lock(settings: makeSettings(), allowsControlCUnlock: true)
    XCTAssertNil(engine.handleEvent(type: .keyDown, event: controlC))
    await flushMainQueue()
    XCTAssertFalse(engine.isLocked)
  }

  // MARK: - Event tap failure

  func testTapDisabledAndReenabledKeepsLock() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    tap.isEnabled = false
    let event = makeKeyEvent(keyCode: 0)
    XCTAssertNotNil(engine.handleDisabledEvent(event))

    await flushMainQueue()

    XCTAssertTrue(engine.isLocked)
    XCTAssertEqual(tap.setEnabledCalls, [true])
    XCTAssertEqual(tap.teardownCallCount, 0)
    XCTAssertEqual(broadcastCount, 1)
  }

  func testTapDisabledBeyondRecoveryUnlocksFailOpen() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    tap.isEnabled = false
    tap.allowsReEnable = false
    let event = makeKeyEvent(keyCode: 0)
    XCTAssertNotNil(engine.handleDisabledEvent(event))
    XCTAssertTrue(engine.isLocked)

    await flushMainQueue()

    XCTAssertFalse(engine.isLocked)
    XCTAssertEqual(tap.teardownCallCount, 1)
    XCTAssertEqual(broadcastCount, 2)
  }

  func testStaleTapFailureKeepsNewerLock() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    tap.isEnabled = false
    tap.allowsReEnable = false
    let event = makeKeyEvent(keyCode: 0)
    XCTAssertNotNil(engine.handleDisabledEvent(event))

    engine.unlock()
    tap.isEnabled = true
    tap.allowsReEnable = true
    _ = try engine.lock(settings: makeSettings())

    await flushMainQueue()

    XCTAssertTrue(engine.isLocked)
  }

  // MARK: - Unlock

  func testUnlockCancelsTimerTearsDownAndBroadcasts() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    engine.unlock()

    XCTAssertFalse(engine.isLocked)
    XCTAssertTrue(scheduler.timers[0].isCancelled)
    XCTAssertEqual(tap.teardownCallCount, 1)
    XCTAssertEqual(broadcastCount, 2)
    XCTAssertNil(engine.statusSnapshot.autoUnlockTargetDate)
  }

  // MARK: - Focus ownership

  func testFocusDeactivationReleasesFocusOwnedLock() throws {
    let engine = makeEngine()
    try engine.setFocusFilterLockEnabled(true, settings: makeSettings())
    XCTAssertTrue(engine.isLocked)

    try engine.setFocusFilterLockEnabled(false, settings: makeSettings())

    XCTAssertFalse(engine.isLocked)
    XCTAssertEqual(tap.teardownCallCount, 1)
  }

  func testFocusDeactivationKeepsLockTakenOverByGeneralRequest() throws {
    let engine = makeEngine()
    try engine.setFocusFilterLockEnabled(true, settings: makeSettings())

    // An explicit lock takes persistence over from the Focus-created generation.
    let takeover = try engine.lock(settings: makeSettings())
    XCTAssertEqual(takeover, .alreadyLocked)

    try engine.setFocusFilterLockEnabled(false, settings: makeSettings())

    XCTAssertTrue(engine.isLocked)
    XCTAssertEqual(tap.teardownCallCount, 0)
  }

  // MARK: - Helpers

  private func makeEngine() -> LockEngine {
    LockEngine(dependencies: LockEngineDependencies(
      hasAccessibilityPermission: { self.hasAccessibilityPermission },
      installEventTap: { _ in
        self.installCount += 1
        return self.tap
      },
      scheduleTimer: scheduler.scheduler,
      broadcastStateChange: { self.broadcastCount += 1 },
      now: { self.now }
    ))
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
private final class ManualTimerScheduler {
  final class Timer {
    let interval: TimeInterval
    private let fireAction: @MainActor () -> Void
    private(set) var isCancelled = false

    init(interval: TimeInterval, fire: @escaping @MainActor () -> Void) {
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
