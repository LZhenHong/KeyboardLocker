import Common
@testable import Service
import XCTest

@MainActor
final class AgentServiceTests: XCTestCase {
  private var engine: FakeLockEngine!
  private var scheduler: ManualExpirationScheduler!
  private var instanceID: UUID!
  private var customSettings: KeyboardLockerSettings!

  override func setUp() {
    super.setUp()
    engine = FakeLockEngine()
    scheduler = ManualExpirationScheduler()
    instanceID = UUID()
    customSettings = KeyboardLockerSettings(
      autoUnlockPolicy: .disabled,
      unlockHotkey: KeyboardLockerSettings.Hotkey(keyCode: 4, modifierFlags: .maskShift)
    )
  }

  // MARK: - Replacement barrier

  func testPreparedDrainRejectsNewLockRequests() {
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
    XCTAssertEqual(interactiveOutcome, false)
    assertReplacementError(interactiveError, code: 1)

    var focusError: Error?
    service.setFocusFilterLockEnabled(true) { focusError = $0 }
    assertReplacementError(focusError, code: 1)

    XCTAssertTrue(engine.lockCalls.isEmpty)
    XCTAssertTrue(engine.focusCalls.isEmpty)
  }

  func testDrainKeepsUnlockStatusAndSnapshotAvailable() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    var unlockError: Error?
    service.unlockKeyboard { unlockError = $0 }
    XCTAssertNil(unlockError)
    XCTAssertEqual(engine.unlockCallCount, 1)

    var isLocked: Bool?
    service.status { locked, _ in isLocked = locked }
    XCTAssertEqual(isLocked, false)

    var snapshotData: Data?
    var snapshotError: Error?
    service.lockStatusSnapshot { data, error in
      snapshotData = data
      snapshotError = error
    }
    XCTAssertNil(snapshotError)
    XCTAssertNotNil(snapshotData)
  }

  func testPrepareRejectsMismatchedInstanceID() {
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

  func testPrepareRejectsLockedEngineUnlessUnlockRequested() {
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
    XCTAssertEqual(lockedEngine.unlockCallCount, 0)

    let ticket = prepareTicket(on: service, unlockIfNeeded: true, instanceID: instanceID)
    XCTAssertNotNil(ticket)
    XCTAssertEqual(lockedEngine.unlockCallCount, 1)
  }

  func testPrepareInstallsBarrierBeforeUnlocking() {
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
    XCTAssertEqual(pendingDuringUnlock, true)
  }

  func testSecondPrepareIsRejectedAndFirstTicketStillCommits() {
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
    XCTAssertNil(commitError)
    XCTAssertEqual(phase(of: first, on: service), .committed)
  }

  func testCommitWithForeignTicketFails() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    let foreign = ServiceReplacementTicket(id: UUID(), agentInstanceID: instanceID)
    var commitError: Error?
    service.commitReplacement(ticket: encoded(foreign)) { commitError = $0 }
    assertReplacementError(commitError, code: 4)
  }

  func testCommittedDrainCannotBeCancelled() {
    let service = makeService()
    let ticket = prepareTicket(on: service, instanceID: instanceID)

    var commitError: Error?
    service.commitReplacement(ticket: encoded(ticket)) { commitError = $0 }
    XCTAssertNil(commitError)

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

  func testCancelWithForeignTicketFailsWhilePrepared() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    var error: Error?
    service.cancelReplacementPreparation(
      ticket: encoded(ServiceReplacementTicket(id: UUID(), agentInstanceID: instanceID))
    ) { error = $0 }
    assertReplacementError(error, code: 4)
  }

  func testMalformedTicketDataSurfacesDecodeError() {
    let service = makeService()

    var commitError: Error?
    service.commitReplacement(ticket: Data([0x00, 0x01])) { commitError = $0 }
    XCTAssertNotNil(commitError)

    var statusError: Error?
    service.replacementStatus(ticket: Data([0x00, 0x01])) { _, error in
      statusError = error
    }
    XCTAssertNotNil(statusError)
  }

  // MARK: - Expiration scheduling

  func testCommitCancelsScheduledExpiration() {
    let service = makeService()
    let ticket = prepareTicket(on: service, instanceID: instanceID)
    XCTAssertEqual(scheduler.scheduledCount, 1)
    XCTAssertEqual(scheduler.lastInterval, 30)

    var commitError: Error?
    service.commitReplacement(ticket: encoded(ticket)) { commitError = $0 }
    XCTAssertNil(commitError)
    XCTAssertEqual(scheduler.cancelCount, 1)

    // A canceled expiration must not clear the committed drain.
    scheduler.firePending()
    XCTAssertEqual(phase(of: ticket, on: service), .committed)
  }

  func testCancelCancelsScheduledExpiration() {
    let service = makeService()
    let ticket = prepareTicket(on: service, instanceID: instanceID)

    var cancelError: Error?
    service.cancelReplacementPreparation(ticket: encoded(ticket)) { cancelError = $0 }
    XCTAssertNil(cancelError)
    XCTAssertEqual(scheduler.cancelCount, 1)

    var lockError: Error?
    service.lockKeyboard { lockError = $0 }
    XCTAssertNil(lockError)
    XCTAssertEqual(engine.lockCalls.count, 1)
  }

  func testExpirationReturnsAgentToAcceptingLocks() {
    let service = makeService()
    let ticket = prepareTicket(on: service, instanceID: instanceID)
    XCTAssertEqual(replacementPending(on: service), true)

    scheduler.firePending()
    XCTAssertEqual(phase(of: ticket, on: service), .inactive)
    XCTAssertEqual(replacementPending(on: service), false)

    var lockError: Error?
    service.lockKeyboard { lockError = $0 }
    XCTAssertNil(lockError)
  }

  // MARK: - Wiring

  func testPrepareFailsWithoutDescriptor() {
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

  func testDescriptorReportsReplacementPending() {
    let service = makeService()
    XCTAssertEqual(replacementPending(on: service), false)

    prepareTicket(on: service, instanceID: instanceID)
    XCTAssertEqual(replacementPending(on: service), true)
  }

  func testPersistedSettingsSeedEngineAndLockCalls() {
    let service = makeService()
    XCTAssertEqual(engine.seededSettings, [customSettings])

    var lockError: Error?
    service.lockKeyboard { lockError = $0 }
    XCTAssertNil(lockError)
    XCTAssertEqual(engine.lockCalls.count, 1)
    XCTAssertEqual(engine.lockCalls.first?.settings, customSettings)
    XCTAssertEqual(engine.lockCalls.first?.allowsControlCUnlock, false)

    var outcome: Bool?
    service.lockKeyboardInteractively { acquired, _ in outcome = acquired }
    XCTAssertEqual(outcome, true)
    XCTAssertEqual(engine.lockCalls.last?.allowsControlCUnlock, true)

    var focusError: Error?
    service.setFocusFilterLockEnabled(true) { focusError = $0 }
    XCTAssertNil(focusError)
    XCTAssertEqual(engine.focusCalls.first?.settings, customSettings)
  }

  // MARK: - Toggle

  func testToggleLocksUnlockedEngineWithPersistedSettings() {
    let service = makeService()

    var isLocked: Bool?
    var toggleError: Error?
    service.toggleKeyboard { locked, error in
      isLocked = locked
      toggleError = error
    }

    XCTAssertNil(toggleError)
    XCTAssertEqual(isLocked, true)
    XCTAssertEqual(engine.lockCalls.count, 1)
    XCTAssertEqual(engine.lockCalls.first?.settings, customSettings)
    XCTAssertEqual(engine.lockCalls.first?.allowsControlCUnlock, false)
    XCTAssertEqual(engine.unlockCallCount, 0)
  }

  func testToggleUnlocksLockedEngine() {
    let lockedEngine = FakeLockEngine(isLocked: true)
    let service = makeService(engineOverride: lockedEngine)

    var isLocked: Bool?
    var toggleError: Error?
    service.toggleKeyboard { locked, error in
      isLocked = locked
      toggleError = error
    }

    XCTAssertNil(toggleError)
    XCTAssertEqual(isLocked, false)
    XCTAssertEqual(lockedEngine.unlockCallCount, 1)
    XCTAssertTrue(lockedEngine.lockCalls.isEmpty)
  }

  func testTogglePropagatesLockFailureWithoutChangingState() {
    engine.lockError = StubError.descriptorUnavailable
    let service = makeService()

    var isLocked: Bool?
    var toggleError: Error?
    service.toggleKeyboard { locked, error in
      isLocked = locked
      toggleError = error
    }

    XCTAssertEqual(toggleError as? StubError, .descriptorUnavailable)
    XCTAssertEqual(isLocked, false)
    XCTAssertFalse(engine.isLocked)
  }

  func testPreparedDrainRejectsOnlyTheLockDirectionOfToggle() {
    let service = makeService()
    prepareTicket(on: service, instanceID: instanceID)

    var toggleError: Error?
    service.toggleKeyboard { _, error in toggleError = error }
    assertReplacementError(toggleError, code: 1)
    XCTAssertTrue(engine.lockCalls.isEmpty)
    XCTAssertEqual(engine.unlockCallCount, 0)
  }

  // MARK: - Fixtures

  private func makeService(
    descriptorResult: Result<ServiceDescriptor, Error>? = nil,
    engineOverride: FakeLockEngine? = nil
  ) -> AgentService {
    AgentService(
      descriptorResult: descriptorResult ?? .success(makeDescriptor(instanceID: instanceID)),
      settings: customSettings,
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
    XCTAssertNil(error)
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
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let nsError = error as NSError?
    XCTAssertEqual(
      nsError?.domain,
      "\(SharedConstants.agentBundleIdentifier).replacement",
      file: file,
      line: line
    )
    XCTAssertEqual(nsError?.code, code, file: file, line: line)
  }
}

private enum StubError: Error {
  case descriptorUnavailable
}

@MainActor
private final class FakeLockEngine: LockEngineServing {
  var isLocked: Bool
  var lockError: Error?
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
    isLocked = true
    return .acquired
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

private final class ManualExpirationScheduler {
  private(set) var scheduledCount = 0
  private(set) var lastInterval: TimeInterval?
  private(set) var cancelCount = 0
  private var pendingFire: (@MainActor () -> Void)?

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
