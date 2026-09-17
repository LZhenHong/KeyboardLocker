import Carbon
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
  private var blockedInputCount: Int
  private var hasAccessibilityPermission: Bool
  private var now: Date
  private var wakeHandler: (@MainActor @Sendable () -> Void)?
  private var keyCodesByCharacter: [Character: CGKeyCode]

  init() {
    tap = FakeInstalledEventTap()
    scheduler = ManualTimerScheduler()
    installCount = 0
    broadcastCount = 0
    stateChangeCount = 0
    blockedInputCount = 0
    hasAccessibilityPermission = true
    now = Date(timeIntervalSinceReferenceDate: 1000)
    wakeHandler = nil
    keyCodesByCharacter = [:]
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

  // MARK: - Blocked-input feedback

  @Test
  func swallowedKeyDownReportsOncePerThrottleWindow() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())
    let event = makeKeyEvent(keyCode: 40)

    #expect(engine.handleEvent(type: .keyDown, event: event) == nil)
    #expect(blockedInputCount == 1)

    // Inside the window a burst collapses into the one report.
    #expect(engine.handleEvent(type: .keyDown, event: event) == nil)
    #expect(blockedInputCount == 1)

    now = now.addingTimeInterval(5)
    #expect(engine.handleEvent(type: .keyDown, event: event) == nil)
    #expect(blockedInputCount == 2)
  }

  @Test
  func blockedInputReportRespectsSettingsGate() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(blockedInputFeedbackEnabled: false))

    #expect(engine.handleEvent(type: .keyDown, event: makeKeyEvent(keyCode: 40)) == nil)
    #expect(blockedInputCount == 0)
  }

  @Test
  func unlockHotkeyDoesNotReportBlockedInput() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    let event = makeKeyEvent(keyCode: 4, flags: .maskShift)
    #expect(engine.handleEvent(type: .keyDown, event: event) == nil)
    #expect(blockedInputCount == 0)
  }

  @Test
  func keyUpAndFlagsChangedDoNotReportBlockedInput() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    #expect(engine.handleEvent(type: .keyUp, event: makeKeyEvent(keyCode: 40)) == nil)
    #expect(engine.handleEvent(type: .flagsChanged, event: makeKeyEvent(keyCode: 56)) == nil)
    #expect(blockedInputCount == 0)
  }

  @Test
  func phraseInputReportsAtMostOnceAndMatchReportsNothing() async throws {
    let engine = makeEngine()
    keyCodesByCharacter = ["a": 0, "b": 1, "c": 2]
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "abc"))

    type("abc", on: engine)
    // 'a' nudges once, 'b' falls inside the throttle window, and 'c' completes the phrase.
    #expect(blockedInputCount == 1)

    await flushMainQueue()
    #expect(!engine.isLocked)
  }

  @Test
  func newLockGenerationReArmsBlockedInputReport() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())
    #expect(engine.handleEvent(type: .keyDown, event: makeKeyEvent(keyCode: 40)) == nil)
    #expect(blockedInputCount == 1)

    engine.unlock()
    _ = try engine.lock(settings: makeSettings())

    // Still inside the previous window, but a fresh generation reports immediately.
    #expect(engine.handleEvent(type: .keyDown, event: makeKeyEvent(keyCode: 40)) == nil)
    #expect(blockedInputCount == 2)
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

  // MARK: - Wake reconciliation

  @Test
  func wakeAfterDeadlineUnlocksAtOnce() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    // The monotonic timer paused while the system slept past the wall-clock deadline.
    now = now.addingTimeInterval(120)
    simulateWake()

    #expect(!engine.isLocked)
    #expect(tap.teardownCallCount == 1)
    #expect(broadcastCount == 2)
    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .autoUnlock, date: now))
  }

  @Test
  func wakeBeforeDeadlineRearmsAgainstTheOriginalDeadline() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())
    let originalDeadline = now.addingTimeInterval(60)

    // Thirty wall-clock seconds passed while the monotonic timer stood still.
    now = now.addingTimeInterval(30)
    simulateWake()

    #expect(engine.isLocked)
    #expect(scheduler.timers.count == 2)
    #expect(scheduler.timers[0].isCancelled)
    #expect(scheduler.timers[1].interval == 30)
    // The published deadline never drifts with a sleep/wake cycle.
    #expect(engine.statusSnapshot.autoUnlockTargetDate == originalDeadline)

    now = originalDeadline
    scheduler.timers[1].fire()
    #expect(!engine.isLocked)
    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .autoUnlock, date: now))
  }

  @Test
  func wakeWithoutLockOrDeadlineIsANoOp() throws {
    let engine = makeEngine()

    simulateWake()
    #expect(scheduler.timers.isEmpty)
    #expect(broadcastCount == 0)

    _ = try engine.lock(settings: makeSettings(autoUnlockPolicy: .disabled))
    simulateWake()

    #expect(engine.isLocked)
    #expect(scheduler.timers.isEmpty)
    #expect(broadcastCount == 1)
  }

  @Test
  func staleWakeRearmCannotUnlockANewerLock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    now = now.addingTimeInterval(30)
    simulateWake()
    let rearmedTimer = scheduler.timers[1]

    engine.unlock()
    _ = try engine.lock(settings: makeSettings())
    #expect(scheduler.timers.count == 3)

    // The re-armed timer's cancel lost the race against an already-queued fire; the
    // generation fence must protect the newer lock.
    rearmedTimer.fire()
    #expect(engine.isLocked)
  }

  // MARK: - Last unlock record

  @Test
  func explicitUnlockIsRecordedWithTheAgentClock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    now = now.addingTimeInterval(10)
    engine.unlock()

    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .explicit, date: now))
  }

  @Test
  func unlockGestureIsRecorded() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    let event = makeKeyEvent(keyCode: 4, flags: .maskShift)
    #expect(engine.handleEvent(type: .keyDown, event: event) == nil)
    await flushMainQueue()

    #expect(!engine.isLocked)
    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .gesture, date: now))
  }

  @Test
  func autoUnlockTimerFireIsRecorded() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    scheduler.timers[0].fire()

    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .autoUnlock, date: now))
  }

  @Test
  func focusConditionalReleaseIsRecorded() throws {
    let engine = makeEngine()
    try engine.setFocusFilterLockEnabled(true, settings: makeSettings())

    try engine.setFocusFilterLockEnabled(false, settings: makeSettings())

    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .focusFilter, date: now))
  }

  @Test
  func eventTapFailureFailOpenIsRecorded() async throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    tap.isEnabled = false
    tap.allowsReEnable = false
    let event = makeKeyEvent(keyCode: 0)
    #expect(engine.handleDisabledEvent(event) != nil)
    await flushMainQueue()

    #expect(!engine.isLocked)
    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .eventTapFailure, date: now))
  }

  @Test
  func runningLockKeepsThePreviousUnlockRecordUntilTheNextUnlock() throws {
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())
    engine.unlock()
    let firstRecord = try #require(engine.statusSnapshot.lastUnlock)

    _ = try engine.lock(settings: makeSettings())
    // A new lock does not erase how the previous one ended.
    #expect(engine.statusSnapshot.lastUnlock == firstRecord)

    now = now.addingTimeInterval(5)
    engine.unlock()
    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .explicit, date: now))
  }

  // MARK: - Unlock phrase

  @Test
  func typingThePhraseUnlocksWithPhraseReason() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))

    type("cat", on: engine)
    // The unlock gesture dispatches async so the tap callback stays non-blocking.
    #expect(engine.isLocked)
    await flushMainQueue()

    #expect(!engine.isLocked)
    #expect(tap.teardownCallCount == 1)
    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .phrase, date: now))
  }

  @Test
  func wrongInputKeepsTheLockAndTheNextAttemptCanMatch() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))

    type("ctt", on: engine) // rolling buffer holds "ctt", never the phrase
    await flushMainQueue()
    #expect(engine.isLocked)

    type("cat", on: engine)
    await flushMainQueue()
    #expect(!engine.isLocked)
  }

  @Test
  func backspaceEditsTheRollingBuffer() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))

    type("ct", on: engine)
    let backspace = makeKeyEvent(keyCode: CGKeyCode(kVK_Delete))
    #expect(engine.handleEvent(type: .keyDown, event: backspace) == nil)
    type("at", on: engine)
    await flushMainQueue()

    #expect(!engine.isLocked)
  }

  @Test
  func modifierChordResetsTheBuffer() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))

    type("ca", on: engine)
    let chord = makeKeyEvent(keyCode: 101, flags: .maskCommand)
    #expect(engine.handleEvent(type: .keyDown, event: chord) == nil)
    type("t", on: engine)
    await flushMainQueue()
    #expect(engine.isLocked)

    type("cat", on: engine)
    await flushMainQueue()
    #expect(!engine.isLocked)
  }

  @Test
  func autoRepeatNeitherCompletesNorBreaksAPhrase() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))

    type("c", on: engine)
    let heldA = makeKeyEvent(keyCode: 101, autorepeat: 1)
    #expect(engine.handleEvent(type: .keyDown, event: heldA) == nil)
    type("at", on: engine)
    await flushMainQueue()

    #expect(!engine.isLocked)
  }

  @Test
  func nonCharacterKeyResetsTheBuffer() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))

    type("ca", on: engine)
    let arrowKey = makeKeyEvent(keyCode: 200) // no character mapping
    #expect(engine.handleEvent(type: .keyDown, event: arrowKey) == nil)
    type("t", on: engine)
    await flushMainQueue()

    #expect(engine.isLocked)
  }

  @Test
  func phraseBufferDoesNotSurviveARelock() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))
    type("ca", on: engine)
    engine.unlock()

    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))
    // "t" alone must not complete against the previous lock's partial "ca".
    type("t", on: engine)
    await flushMainQueue()

    #expect(engine.isLocked)
  }

  @Test
  func lockWithoutPhraseIgnoresTypedInput() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings())

    type("cat", on: engine)
    await flushMainQueue()

    #expect(engine.isLocked)
    #expect(tap.teardownCallCount == 0)
  }

  @Test
  func duplicateLockKeepsTheOriginalPhraseGesture() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102, "d": 103, "o": 104, "g": 105]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))

    let duplicate = try engine.lock(settings: makeSettings(unlockPhrase: "dog"))
    #expect(duplicate == .alreadyLocked)

    type("cat", on: engine)
    await flushMainQueue()

    #expect(!engine.isLocked)
    #expect(engine.statusSnapshot.lastUnlock == UnlockRecord(reason: .phrase, date: now))
  }

  @Test
  func shiftedCharacterMatchesTheLowercasedPhrase() async throws {
    keyCodesByCharacter = ["c": 100, "a": 101, "t": 102]
    let engine = makeEngine()
    _ = try engine.lock(settings: makeSettings(unlockPhrase: "cat"))

    let shiftedC = makeKeyEvent(keyCode: 100, flags: .maskShift)
    #expect(engine.handleEvent(type: .keyDown, event: shiftedC) == nil)
    type("at", on: engine)
    await flushMainQueue()

    #expect(!engine.isLocked)
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
      characterForKeyCode: { keyCode, shiftDown in
        for (character, code) in self.keyCodesByCharacter where code == keyCode {
          return shiftDown ? Character(character.uppercased()) : character
        }
        return nil
      },
      observeSystemWake: { handler in
        self.wakeHandler = handler
        return { self.wakeHandler = nil }
      },
      broadcastStateChange: { self.broadcastCount += 1 },
      now: { self.now }
    ))
    engine.setStateChangeHandler { self.stateChangeCount += 1 }
    engine.setBlockedInputHandler { self.blockedInputCount += 1 }
    return engine
  }

  /// Delivers the system-wake signal the live dependencies bridge from `NSWorkspace`.
  private func simulateWake() {
    wakeHandler?()
  }

  private func makeSettings(
    autoUnlockPolicy: KeyboardLockerSettings.AutoUnlockPolicy = .timed(seconds: 60),
    unlockPhrase: String? = nil,
    blockedInputFeedbackEnabled: Bool = true
  ) -> KeyboardLockerSettings {
    KeyboardLockerSettings(
      autoUnlockPolicy: autoUnlockPolicy,
      unlockHotkey: KeyboardLockerSettings.Hotkey(keyCode: 4, modifierFlags: .maskShift),
      unlockPhrase: unlockPhrase,
      blockedInputFeedbackEnabled: blockedInputFeedbackEnabled
    )
  }

  private func makeKeyEvent(
    keyCode: CGKeyCode,
    flags: CGEventFlags = [],
    autorepeat: Int64 = 0
  ) -> CGEvent {
    // Fabrication only builds an in-memory event value; nothing is posted to the HID system.
    // Bind the result to a local when asserting on a handler's return: handlers hand the event
    // back unretained, so it must outlive the returned reference.
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    event.flags = flags
    event.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat)
    return event
  }

  /// Feeds each character as a plain key-down through the fabricated event stream. Every
  /// keystroke while locked is consumed, phrase progress or not.
  private func type(_ text: String, on engine: LockEngine) {
    for character in text {
      guard let keyCode = keyCodesByCharacter[character] else {
        Issue.record("No key code registered for '\(character)'")
        continue
      }
      let event = makeKeyEvent(keyCode: keyCode)
      #expect(engine.handleEvent(type: .keyDown, event: event) == nil)
    }
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
