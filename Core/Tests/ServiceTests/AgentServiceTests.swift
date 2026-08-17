import Common
import CoreGraphics
import Foundation
@testable import Service
import Testing

@MainActor
@Suite(.serialized)
final class AgentServiceTests {
  private let engine: FakeLockEngine
  private let scheduler: ManualExpirationScheduler
  private let instanceID: UUID
  private let customSettings: KeyboardLockerSettings
  private let settingsStore: FakeSettingsStore

  init() {
    engine = FakeLockEngine()
    scheduler = ManualExpirationScheduler()
    instanceID = UUID()
    settingsStore = FakeSettingsStore()
    customSettings = KeyboardLockerSettings(
      autoUnlockPolicy: .disabled,
      unlockHotkey: KeyboardLockerSettings.Hotkey(keyCode: 4, modifierFlags: .maskShift)
    )
  }

  // MARK: - Replacement barrier

  @Test
  func preparedDrainRejectsNewLockRequests() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    var lockError: Error?
    service.lockKeyboard { lockError = $0 }
    assertReplacementError(lockError, code: 1)

    var interactiveOutcome: Bool?
    var interactiveError: Error?
    service.lockKeyboardInteractively { outcome, error in
      interactiveOutcome = outcome
      interactiveError = error
    }
    #expect(interactiveOutcome == false)
    assertReplacementError(interactiveError, code: 1)

    var safetyCheckError: Error?
    service.beginSafetyCheck { _, error in safetyCheckError = error }
    assertReplacementError(safetyCheckError, code: 1)

    var focusError: Error?
    service.setFocusFilterLockEnabled(true) { focusError = $0 }
    assertReplacementError(focusError, code: 1)

    #expect(engine.lockCalls.isEmpty)
    #expect(engine.focusCalls.isEmpty)
  }

  @Test
  func drainKeepsUnlockStatusAndSnapshotAvailable() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    var unlockError: Error?
    service.unlockKeyboard { unlockError = $0 }
    #expect(unlockError == nil)
    #expect(engine.unlockCallCount == 1)

    var isLocked: Bool?
    service.status { locked, _ in isLocked = locked }
    #expect(isLocked == false)

    var snapshotData: Data?
    var snapshotError: Error?
    service.lockStatusSnapshot { data, error in
      snapshotData = data
      snapshotError = error
    }
    #expect(snapshotError == nil)
    #expect(snapshotData != nil)
  }

  @Test
  func prepareRejectsMismatchedInstanceID() {
    let service = makeService()

    var error: Error?
    service.prepareForReplacement(
      unlockIfNeeded: false,
      expectedAgentInstanceID: UUID()
    ) { _, replyError in
      error = replyError
    }
    assertReplacementError(error, code: 8)

    // The transaction stays idle, so a correctly fenced prepare still succeeds.
    prepareTicket(on: service, instanceID: instanceID)
  }

  @Test
  func prepareRejectsLockedEngineUnlessUnlockRequested() {
    let lockedEngine = FakeLockEngine(isLocked: true)
    let service = makeService(engineOverride: lockedEngine)

    var error: Error?
    service.prepareForReplacement(
      unlockIfNeeded: false,
      expectedAgentInstanceID: instanceID
    ) { _, replyError in
      error = replyError
    }
    assertReplacementError(error, code: 3)
    #expect(lockedEngine.unlockCallCount == 0)

    let ticket = prepareTicket(on: service, unlockIfNeeded: true, instanceID: instanceID)
    #expect(ticket != nil)
    #expect(lockedEngine.unlockCallCount == 1)
  }

  @Test
  func prepareInstallsBarrierBeforeUnlocking() {
    let lockedEngine = FakeLockEngine(isLocked: true)
    let service = makeService(engineOverride: lockedEngine)

    var pendingDuringUnlock: Bool?
    lockedEngine.onUnlock = { [weak service] in
      guard let service else {
        return
      }
      pendingDuringUnlock = self.replacementPending(on: service)
    }

    prepareTicket(on: service, unlockIfNeeded: true, instanceID: instanceID)
    #expect(pendingDuringUnlock == true)
  }

  @Test
  func secondPrepareIsRejectedAndFirstTicketStillCommits() {
    let service = makeService()
    let first = prepareTicket(on: service, instanceID: instanceID)

    var secondError: Error?
    service.prepareForReplacement(
      unlockIfNeeded: false,
      expectedAgentInstanceID: instanceID
    ) { _, replyError in
      secondError = replyError
    }
    assertReplacementError(secondError, code: 5)

    var commitError: Error?
    service.commitReplacement(ticket: encoded(first)) { commitError = $0 }
    #expect(commitError == nil)
    #expect(phase(of: first, on: service) == .committed)
  }

  @Test
  func commitWithForeignTicketFails() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    let foreign = ServiceReplacementTicket(id: UUID(), agentInstanceID: instanceID)
    var commitError: Error?
    service.commitReplacement(ticket: encoded(foreign)) { commitError = $0 }
    assertReplacementError(commitError, code: 4)
  }

  @Test
  func committedDrainCannotBeCancelled() {
    let service = makeService()
    let ticket = prepareTicket(on: service, instanceID: instanceID)

    var commitError: Error?
    service.commitReplacement(ticket: encoded(ticket)) { commitError = $0 }
    #expect(commitError == nil)

    var cancelError: Error?
    service.cancelReplacementPreparation(ticket: encoded(ticket)) { cancelError = $0 }
    assertReplacementError(cancelError, code: 6)

    // A committed drain rejects every cancel, even for a foreign ticket.
    var foreignCancelError: Error?
    service.cancelReplacementPreparation(
      ticket: encoded(ServiceReplacementTicket(id: UUID(), agentInstanceID: instanceID))
    ) { foreignCancelError = $0 }
    assertReplacementError(foreignCancelError, code: 6)
  }

  @Test
  func cancelWithForeignTicketFailsWhilePrepared() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    var error: Error?
    service.cancelReplacementPreparation(
      ticket: encoded(ServiceReplacementTicket(id: UUID(), agentInstanceID: instanceID))
    ) { error = $0 }
    assertReplacementError(error, code: 4)
  }

  @Test
  func malformedTicketDataSurfacesDecodeError() {
    let service = makeService()

    var commitError: Error?
    service.commitReplacement(ticket: Data([0x00, 0x01])) { commitError = $0 }
    #expect(commitError != nil)

    var statusError: Error?
    service.replacementStatus(ticket: Data([0x00, 0x01])) { _, error in
      statusError = error
    }
    #expect(statusError != nil)
  }

  // MARK: - Expiration scheduling

  @Test
  func commitCancelsScheduledExpiration() {
    let service = makeService()
    let ticket = prepareTicket(on: service, instanceID: instanceID)
    #expect(scheduler.scheduledCount == 1)
    #expect(scheduler.lastInterval == 30)

    var commitError: Error?
    service.commitReplacement(ticket: encoded(ticket)) { commitError = $0 }
    #expect(commitError == nil)
    #expect(scheduler.cancelCount == 1)

    // A canceled expiration must not clear the committed drain.
    scheduler.firePending()
    #expect(phase(of: ticket, on: service) == .committed)
  }

  @Test
  func cancelCancelsScheduledExpiration() {
    let service = makeService()
    let ticket = prepareTicket(on: service, instanceID: instanceID)

    var cancelError: Error?
    service.cancelReplacementPreparation(ticket: encoded(ticket)) { cancelError = $0 }
    #expect(cancelError == nil)
    #expect(scheduler.cancelCount == 1)

    var lockError: Error?
    service.lockKeyboard { lockError = $0 }
    #expect(lockError == nil)
    #expect(engine.lockCalls.count == 1)
  }

  @Test
  func expirationReturnsAgentToAcceptingLocks() {
    let service = makeService()
    let ticket = prepareTicket(on: service, instanceID: instanceID)
    #expect(replacementPending(on: service) == true)

    scheduler.firePending()
    #expect(phase(of: ticket, on: service) == .inactive)
    #expect(replacementPending(on: service) == false)

    var lockError: Error?
    service.lockKeyboard { lockError = $0 }
    #expect(lockError == nil)
  }

  // MARK: - Wiring

  @Test
  func prepareFailsWithoutDescriptor() {
    let service = makeService(
      descriptorResult: .failure(StubError.descriptorUnavailable)
    )

    var error: Error?
    service.prepareForReplacement(
      unlockIfNeeded: false,
      expectedAgentInstanceID: instanceID
    ) { _, replyError in
      error = replyError
    }
    assertReplacementError(error, code: 2)
  }

  @Test
  func descriptorReportsReplacementPending() {
    let service = makeService()
    #expect(replacementPending(on: service) == false)

    prepareTicket(on: service, instanceID: instanceID)
    #expect(replacementPending(on: service) == true)
  }

  @Test
  func persistedSettingsSeedEngineAndLockCalls() {
    let service = makeService()
    #expect(engine.seededSettings == [customSettings])

    var lockError: Error?
    service.lockKeyboard { lockError = $0 }
    #expect(lockError == nil)
    #expect(engine.lockCalls.count == 1)
    #expect(engine.lockCalls.first?.settings == customSettings)
    #expect(engine.lockCalls.first?.allowsControlCUnlock == false)

    var outcome: Bool?
    service.lockKeyboardInteractively { acquired, _ in outcome = acquired }
    #expect(outcome == true)
    #expect(engine.lockCalls.last?.allowsControlCUnlock == true)

    var focusError: Error?
    service.setFocusFilterLockEnabled(true) { focusError = $0 }
    #expect(focusError == nil)
    #expect(engine.focusCalls.first?.settings == customSettings)
  }

  @Test
  func safetyCheckUsesFixedTimedOverrideWithoutChangingPersistedSettings() {
    let service = makeService()

    var didStart: Bool?
    var safetyError: Error?
    service.beginSafetyCheck { started, error in
      didStart = started
      safetyError = error
    }

    #expect(safetyError == nil)
    #expect(didStart == true)
    #expect(
      engine.lockCalls.first?.settings.autoUnlockPolicy ==
        .timed(seconds: SharedConstants.safetyCheckDuration)
    )
    #expect(engine.lockCalls.first?.settings.unlockHotkey == customSettings.unlockHotkey)
    #expect(engine.lockCalls.first?.allowsControlCUnlock == false)

    engine.unlock()
    var lockError: Error?
    service.lockKeyboard { lockError = $0 }
    #expect(lockError == nil)
    #expect(engine.lockCalls.last?.settings == customSettings)
  }

  @Test
  func safetyCheckReportsAnExistingLockWithoutChangingIt() {
    engine.lockOutcome = .alreadyLocked
    let service = makeService()

    var didStart: Bool?
    var safetyError: Error?
    service.beginSafetyCheck { started, error in
      didStart = started
      safetyError = error
    }

    #expect(safetyError == nil)
    #expect(didStart == false)
    #expect(engine.unlockCallCount == 0)
  }

  // MARK: - Toggle

  @Test
  func toggleLocksUnlockedEngineWithPersistedSettings() {
    let service = makeService()

    var isLocked: Bool?
    var toggleError: Error?
    service.toggleKeyboard { locked, error in
      isLocked = locked
      toggleError = error
    }

    #expect(toggleError == nil)
    #expect(isLocked == true)
    #expect(engine.lockCalls.count == 1)
    #expect(engine.lockCalls.first?.settings == customSettings)
    #expect(engine.lockCalls.first?.allowsControlCUnlock == false)
    #expect(engine.unlockCallCount == 0)
  }

  @Test
  func toggleUnlocksLockedEngine() {
    let lockedEngine = FakeLockEngine(isLocked: true)
    let service = makeService(engineOverride: lockedEngine)

    var isLocked: Bool?
    var toggleError: Error?
    service.toggleKeyboard { locked, error in
      isLocked = locked
      toggleError = error
    }

    #expect(toggleError == nil)
    #expect(isLocked == false)
    #expect(lockedEngine.unlockCallCount == 1)
    #expect(lockedEngine.lockCalls.isEmpty)
  }

  @Test
  func togglePropagatesLockFailureWithoutChangingState() {
    engine.lockError = StubError.descriptorUnavailable
    let service = makeService()

    var isLocked: Bool?
    var toggleError: Error?
    service.toggleKeyboard { locked, error in
      isLocked = locked
      toggleError = error
    }

    #expect(toggleError as? StubError == .descriptorUnavailable)
    #expect(isLocked == false)
    #expect(!engine.isLocked)
  }

  @Test
  func preparedDrainRejectsOnlyTheLockDirectionOfToggle() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    var toggleError: Error?
    service.toggleKeyboard { _, error in toggleError = error }
    assertReplacementError(toggleError, code: 1)
    #expect(engine.lockCalls.isEmpty)
    #expect(engine.unlockCallCount == 0)
  }

  // MARK: - Settings writes

  @Test
  func applySettingsPersistsAndSeedsTheEngineWhileUnlocked() throws {
    let service = makeService()
    let desired = makeValidSettings(autoUnlockPolicy: .timed(seconds: 90))

    let applied = try applySettings(desired, on: service)

    #expect(applied == desired)
    #expect(settingsStore.saved == [desired])
    // Unlocked, so the new values may seed the engine immediately for the next lock.
    #expect(engine.seededSettings.last == desired)
  }

  /// Regression gate for the lock-out path: `LockEngine.updateSettings` re-arms the auto-unlock
  /// timer from the moment it is called, and cancels it entirely for `.disabled`. Applying settings
  /// during an active lock must therefore never reach the engine.
  @Test
  func applySettingsWhileLockedPersistsWithoutTouchingTheRunningLock() throws {
    let engine = FakeLockEngine(isLocked: true)
    let service = makeService(engineOverride: engine)
    let seededBeforeWrite = engine.seededSettings
    let desired = makeValidSettings(autoUnlockPolicy: .disabled)

    let applied = try applySettings(desired, on: service)

    #expect(applied == desired)
    #expect(settingsStore.saved == [desired])
    // The running lock keeps its active settings, gesture, start time, and deadline.
    #expect(engine.seededSettings == seededBeforeWrite)
    #expect(engine.unlockCallCount == 0)
    #expect(engine.lockCalls.isEmpty)
    #expect(engine.isLocked)
  }

  @Test
  func appliedSettingsBecomeTheValuesReportedAndUsedForTheNextLock() throws {
    let service = makeService()
    let desired = makeValidSettings(autoUnlockPolicy: .timed(seconds: 30))

    _ = try applySettings(desired, on: service)

    var reported: KeyboardLockerSettings?
    service.currentSettingsWithError { data, _ in
      reported = try? KeyboardLockerSettings.decodedFromXPC(data)
    }
    #expect(reported == desired)

    service.lockKeyboard { _ in }
    #expect(engine.lockCalls.last?.settings == desired)
  }

  @Test
  func applySettingsNormalizesBeforeReplyingSoCallersAdoptTheStoredValues() throws {
    let service = makeService()
    let desired = makeValidSettings(autoUnlockPolicy: .timed(seconds: 59.6))

    let applied = try applySettings(desired, on: service)

    #expect(applied.autoUnlockPolicy == .timed(seconds: 60))
    #expect(settingsStore.saved == [applied])
  }

  @Test
  func applySettingsRejectsAnInvalidPayloadWithoutPersisting() throws {
    let service = makeService()
    let invalid = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: KeyboardLockerSettings.Hotkey(keyCode: 37, modifierFlags: [])
    )

    var error: Error?
    var data: Data?
    try service.applySettings(invalid.encodedForXPC()) { replyData, replyError in
      data = replyData
      error = replyError
    }

    #expect(data == nil)
    #expect(
      error as? KeyboardLockerSettingsValidationError == .hotkeyMissingModifier
    )
    #expect(settingsStore.saved.isEmpty)
  }

  @Test
  func applySettingsRejectsUndecodablePayloadWithoutPersisting() {
    let service = makeService()

    var error: Error?
    service.applySettings(Data("not settings".utf8)) { _, replyError in
      error = replyError
    }

    #expect(
      error as? KeyboardLockerSettingsCodingError == .invalidPayload
    )
    #expect(settingsStore.saved.isEmpty)
  }

  @Test
  func applySettingsKeepsPreviousValuesWhenPersistenceFails() throws {
    let service = makeService()
    settingsStore.saveError = StubError.descriptorUnavailable

    var error: Error?
    try service.applySettings(
      makeValidSettings(autoUnlockPolicy: .timed(seconds: 30)).encodedForXPC()
    ) { _, replyError in
      error = replyError
    }

    #expect(error as? StubError == .descriptorUnavailable)
    #expect(settingsStore.saved.isEmpty)

    // A failed write must not become the in-memory source of truth.
    var reported: KeyboardLockerSettings?
    service.currentSettingsWithError { data, _ in
      reported = try? KeyboardLockerSettings.decodedFromXPC(data)
    }
    #expect(reported == customSettings)
  }

  @Test
  func preparedDrainRejectsSettingsWrites() throws {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    var error: Error?
    try service.applySettings(
      makeValidSettings(autoUnlockPolicy: .timed(seconds: 30)).encodedForXPC()
    ) { _, replyError in
      error = replyError
    }

    assertReplacementError(error, code: 1)
    #expect(settingsStore.saved.isEmpty)
  }

  // MARK: - Fixtures

  private func makeValidSettings(
    autoUnlockPolicy: KeyboardLockerSettings.AutoUnlockPolicy
  ) -> KeyboardLockerSettings {
    KeyboardLockerSettings(
      autoUnlockPolicy: autoUnlockPolicy,
      unlockHotkey: KeyboardLockerSettings.Hotkey(
        keyCode: CGKeyCode(SharedConstants.defaultUnlockKeyCode),
        modifierFlags: [.maskControl, .maskAlternate]
      )
    )
  }

  private func applySettings(
    _ settings: KeyboardLockerSettings,
    on service: AgentService
  ) throws -> KeyboardLockerSettings {
    var data: Data?
    var error: Error?
    try service.applySettings(settings.encodedForXPC()) { replyData, replyError in
      data = replyData
      error = replyError
    }
    #expect(error == nil)
    return try KeyboardLockerSettings.decodedFromXPC(data)
  }

  private func makeService(
    descriptorResult: Result<ServiceDescriptor, Error>? = nil,
    engineOverride: FakeLockEngine? = nil
  ) -> AgentService {
    AgentService(
      descriptorResult: descriptorResult ?? .success(makeDescriptor(instanceID: instanceID)),
      settings: customSettings,
      settingsStore: settingsStore,
      engine: engineOverride ?? engine,
      expirationScheduler: scheduler.scheduler
    )
  }

  private func makeDescriptor(instanceID: UUID) -> ServiceDescriptor {
    ServiceDescriptor(
      protocolVersion: ServiceContract.protocolVersion,
      capabilities: ServiceContract.requiredCapabilities,
      agentBundleIdentifier: SharedConstants.agentBundleIdentifier,
      agentVersion: "1.0",
      agentBuild: "100",
      agentInstanceID: instanceID,
      replacementPending: false,
      replacementPhase: .inactive
    )
  }

  @discardableResult
  private func prepareTicket(
    on service: AgentService,
    unlockIfNeeded: Bool = false,
    instanceID: UUID
  ) -> ServiceReplacementTicket? {
    var data: Data?
    var error: Error?
    service.prepareForReplacement(
      unlockIfNeeded: unlockIfNeeded,
      expectedAgentInstanceID: instanceID
    ) { ticketData, replyError in
      data = ticketData
      error = replyError
    }
    #expect(error == nil)
    return data.flatMap { try? ServiceReplacementTicket.decodedFromXPC($0) }
  }

  private func encoded(_ ticket: ServiceReplacementTicket?) -> Data {
    (try? ticket?.encodedForXPC()) ?? Data()
  }

  private func phase(
    of ticket: ServiceReplacementTicket?,
    on service: AgentService
  ) -> ServiceReplacementPhase? {
    var data: Data?
    service.replacementStatus(ticket: encoded(ticket)) { statusData, _ in
      data = statusData
    }
    return data.flatMap { try? ServiceReplacementStatus.decodedFromXPC($0) }?.phase
  }

  private func replacementPending(on service: AgentService) -> Bool? {
    var data: Data?
    service.serviceDescriptor { descriptorData, _ in
      data = descriptorData
    }
    return data.flatMap { try? ServiceDescriptor.decodedFromXPC($0) }?.replacementPending
  }

  private func assertReplacementError(
    _ error: Error?,
    code: Int,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let nsError = error as NSError?
    #expect(
      nsError?.domain == "\(SharedConstants.agentBundleIdentifier).replacement",
      sourceLocation: sourceLocation
    )
    #expect(nsError?.code == code, sourceLocation: sourceLocation)
  }
}

private enum StubError: Error {
  case descriptorUnavailable
}

@MainActor
private final class FakeLockEngine: LockEngineServing {
  var isLocked: Bool
  var lockError: Error?
  var lockOutcome: LockRequestOutcome = .acquired
  var onUnlock: (() -> Void)?

  private let snapshot: LockStatusSnapshot
  private(set) var lockCalls:
    [(settings: KeyboardLockerSettings, allowsControlCUnlock: Bool)] = []
  private(set) var unlockCallCount = 0
  private(set) var focusCalls: [(enabled: Bool, settings: KeyboardLockerSettings)] = []
  private(set) var seededSettings: [KeyboardLockerSettings] = []

  init(isLocked: Bool = false) {
    self.isLocked = isLocked
    snapshot = LockStatusSnapshot(
      capturedAt: Date(timeIntervalSinceReferenceDate: 0),
      isLocked: isLocked,
      startedAt: nil,
      autoUnlockTargetDate: nil,
      settings: .default
    )
  }

  var statusSnapshot: LockStatusSnapshot {
    snapshot
  }

  func lock(
    settings: KeyboardLockerSettings,
    allowsControlCUnlock: Bool
  ) throws -> LockRequestOutcome {
    lockCalls.append((settings, allowsControlCUnlock))
    if let lockError {
      throw lockError
    }
    if lockOutcome == .acquired {
      isLocked = true
    }
    return lockOutcome
  }

  func setFocusFilterLockEnabled(
    _ enabled: Bool,
    settings: KeyboardLockerSettings
  ) throws {
    focusCalls.append((enabled, settings))
  }

  func unlock() {
    unlockCallCount += 1
    isLocked = false
    onUnlock?()
  }

  func updateSettings(_ settings: KeyboardLockerSettings) {
    seededSettings.append(settings)
  }
}

@MainActor
private final class FakeSettingsStore: SettingsPersisting {
  var saveError: Error?
  private(set) var saved: [KeyboardLockerSettings] = []

  nonisolated init() {}

  nonisolated func save(_ settings: KeyboardLockerSettings) throws {
    try MainActor.assumeIsolated {
      if let saveError {
        throw saveError
      }
      saved.append(settings)
    }
  }
}

@MainActor
private final class ManualExpirationScheduler {
  private(set) var scheduledCount = 0
  private(set) var lastInterval: TimeInterval?
  private(set) var cancelCount = 0
  private var pendingFire: (@MainActor @Sendable () -> Void)?

  var scheduler: MainActorTimerScheduler {
    { interval, fire in
      self.scheduledCount += 1
      self.lastInterval = interval
      self.pendingFire = fire
      return { [weak self] in
        guard let self else {
          return
        }
        cancelCount += 1
        pendingFire = nil
      }
    }
  }

  @MainActor
  func firePending() {
    pendingFire?()
  }
}
