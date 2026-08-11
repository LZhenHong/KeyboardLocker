import Client
import Foundation
import XCTest

final class AgentReplacementCoordinatorTests: XCTestCase {
  @MainActor
  func testSafePlanPreparesAndCommitsBeforeRestarting() async {
    let log = ReplacementCallLog()
    let descriptor = makeDescriptor()
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: descriptor.agentInstanceID
    )
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .safe(descriptor: descriptor, isLocked: true),
      message: "Update required."
    )

    _ = await coordinator.replace(plan)

    XCTAssertEqual(log.steps, [.prepare, .commit, .restart, .resetConnection])
    XCTAssertEqual(client.prepareCalls.count, 1)
    XCTAssertEqual(client.prepareCalls.first?.unlockIfNeeded, true)
    XCTAssertEqual(
      client.prepareCalls.first?.expectedAgentInstanceID,
      descriptor.agentInstanceID
    )
    XCTAssertEqual(client.committedTickets, [ticket])
    XCTAssertTrue(client.cancelledTickets.isEmpty)
  }

  @MainActor
  func testSafePlanRestartSuccessReturnsRestartedAndResetsConnection() async {
    let log = ReplacementCallLog()
    let descriptor = makeDescriptor()
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: descriptor.agentInstanceID
    )
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .safe(descriptor: descriptor, isLocked: false),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .restarted(previousAgentInstanceID) = outcome else {
      XCTFail("Expected .restarted, got \(outcome).")
      return
    }
    XCTAssertEqual(previousAgentInstanceID, descriptor.agentInstanceID)
    XCTAssertEqual(client.resetConnectionCallCount, 1)
  }

  @MainActor
  func testCommittedSafePlanRestartFailureDoesNotCancelPreparation() async {
    let log = ReplacementCallLog()
    let descriptor = makeDescriptor()
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: descriptor.agentInstanceID
    )
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    lifecycle.restartResult = .approvalRequired
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .safe(descriptor: descriptor, isLocked: true),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .registration(state) = outcome else {
      XCTFail("Expected .registration, got \(outcome).")
      return
    }
    XCTAssertEqual(state, .approvalRequired)
    XCTAssertEqual(client.committedTickets, [ticket])
    XCTAssertTrue(client.cancelledTickets.isEmpty)
    XCTAssertEqual(client.resetConnectionCallCount, 1)
    XCTAssertEqual(log.steps, [.prepare, .commit, .restart, .resetConnection])
  }

  @MainActor
  func testPrepareFailureReportsFailedWithCurrentLockState() async {
    let log = ReplacementCallLog()
    let descriptor = makeDescriptor()
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: descriptor.agentInstanceID
    )
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    client.prepareError = TestError.expected
    client.statusResult = .success(true)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .safe(descriptor: descriptor, isLocked: true),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .failed(error, currentLockState) = outcome else {
      XCTFail("Expected .failed, got \(outcome).")
      return
    }
    XCTAssertEqual(error as? TestError, .expected)
    XCTAssertEqual(currentLockState, true)
    XCTAssertTrue(client.cancelledTickets.isEmpty)
    XCTAssertEqual(client.statusCallCount, 1)
    XCTAssertEqual(log.steps, [.prepare, .serviceDescriptor, .status])
  }

  @MainActor
  func testCommitFailureCancelsPreparedTicketThenReportsFailed() async {
    let log = ReplacementCallLog()
    let descriptor = makeDescriptor()
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: descriptor.agentInstanceID
    )
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    client.commitError = TestError.expected
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .safe(descriptor: descriptor, isLocked: false),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .failed(error, currentLockState) = outcome else {
      XCTFail("Expected .failed, got \(outcome).")
      return
    }
    XCTAssertEqual(error as? TestError, .expected)
    XCTAssertEqual(currentLockState, false)
    XCTAssertEqual(client.cancelledTickets, [ticket])
    XCTAssertTrue(client.committedTickets.isEmpty)
    XCTAssertEqual(
      log.steps,
      [.prepare, .commit, .cancel, .serviceDescriptor, .status]
    )
  }

  @MainActor
  func testSafePlanFailureRedetectsTrustedReplacementInProgress() async {
    let log = ReplacementCallLog()
    let descriptor = makeDescriptor()
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: descriptor.agentInstanceID
    )
    let pendingDescriptor = makeDescriptor(replacementPending: true)
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    client.commitError = TestError.expected
    client.descriptorResult = .success(pendingDescriptor)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .safe(descriptor: descriptor, isLocked: true),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .replacementInProgress(reported) = outcome else {
      XCTFail("Expected .replacementInProgress, got \(outcome).")
      return
    }
    XCTAssertEqual(reported, pendingDescriptor)
    XCTAssertEqual(client.cancelledTickets, [ticket])
    XCTAssertEqual(client.statusCallCount, 0)
  }

  @MainActor
  func testForcedPlanFailureDoesNotRedetectReplacementInProgress() async {
    let log = ReplacementCallLog()
    let ticket = ServiceReplacementTicket(id: UUID(), agentInstanceID: UUID())
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    client.unlockError = TestError.expected
    client.descriptorResult = .success(makeDescriptor(replacementPending: true))
    client.statusResult = .success(true)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .forced(descriptor: makeDescriptor(), isLocked: true),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .failed(error, currentLockState) = outcome else {
      XCTFail("Expected .failed, got \(outcome).")
      return
    }
    XCTAssertEqual(error as? TestError, .expected)
    XCTAssertEqual(currentLockState, true)
    XCTAssertEqual(client.descriptorCallCount, 0)
    XCTAssertEqual(log.steps, [.unlock, .status])
  }

  @MainActor
  func testForcedPlanWithKnownLockStateUnlocksBeforeRestarting() async {
    let log = ReplacementCallLog()
    let descriptor = makeDescriptor()
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: descriptor.agentInstanceID
    )
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .forced(descriptor: descriptor, isLocked: true),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .restarted(previousAgentInstanceID) = outcome else {
      XCTFail("Expected .restarted, got \(outcome).")
      return
    }
    XCTAssertEqual(previousAgentInstanceID, descriptor.agentInstanceID)
    XCTAssertEqual(client.unlockCallCount, 1)
    XCTAssertTrue(client.prepareCalls.isEmpty)
    XCTAssertTrue(client.committedTickets.isEmpty)
    XCTAssertTrue(client.cancelledTickets.isEmpty)
    XCTAssertEqual(log.steps, [.unlock, .restart, .resetConnection])
  }

  @MainActor
  func testForcedPlanWithKnownLockStateRestartFailureReturnsRegistration() async {
    let log = ReplacementCallLog()
    let descriptor = makeDescriptor()
    let ticket = ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: descriptor.agentInstanceID
    )
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    lifecycle.restartResult = .approvalRequired
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .forced(descriptor: descriptor, isLocked: true),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .registration(state) = outcome else {
      XCTFail("Expected .registration, got \(outcome).")
      return
    }
    XCTAssertEqual(state, .approvalRequired)
    XCTAssertEqual(client.unlockCallCount, 1)
    XCTAssertTrue(client.cancelledTickets.isEmpty)
    XCTAssertEqual(log.steps, [.unlock, .restart, .resetConnection])
  }

  @MainActor
  func testForcedPlanWithUnknownLockStateSkipsUnlock() async {
    let log = ReplacementCallLog()
    let ticket = ServiceReplacementTicket(id: UUID(), agentInstanceID: UUID())
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .forced(descriptor: nil, isLocked: nil),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .restarted(previousAgentInstanceID) = outcome else {
      XCTFail("Expected .restarted, got \(outcome).")
      return
    }
    XCTAssertNil(previousAgentInstanceID)
    XCTAssertEqual(client.unlockCallCount, 0)
    XCTAssertEqual(client.statusCallCount, 0)
    XCTAssertEqual(log.steps, [.restart, .resetConnection])
  }

  @MainActor
  func testForcedPlanRestartFailureReturnsRegistration() async {
    let log = ReplacementCallLog()
    let ticket = ServiceReplacementTicket(id: UUID(), agentInstanceID: UUID())
    let client = FakeAgentReplacementClient(log: log, ticket: ticket)
    let lifecycle = FakeAgentReplacementLifecycle(log: log)
    lifecycle.restartResult = .unavailable(.restartFailed("Restart failed for testing."))
    let coordinator = AgentReplacementCoordinator(client: client, lifecycle: lifecycle)
    let plan = AgentUpdatePlan(
      mode: .forced(descriptor: nil, isLocked: nil),
      message: "Update required."
    )

    let outcome = await coordinator.replace(plan)

    guard case let .registration(state) = outcome else {
      XCTFail("Expected .registration, got \(outcome).")
      return
    }
    XCTAssertEqual(state, .unavailable(.restartFailed("Restart failed for testing.")))
    XCTAssertEqual(client.resetConnectionCallCount, 1)
    XCTAssertEqual(log.steps, [.restart, .resetConnection])
  }
}

@MainActor
private final class ReplacementCallLog {
  enum Step: Equatable {
    case cancel
    case commit
    case prepare
    case resetConnection
    case restart
    case serviceDescriptor
    case status
    case unlock
  }

  private(set) var steps: [Step] = []

  func record(_ step: Step) {
    steps.append(step)
  }
}

@MainActor
private final class FakeAgentReplacementClient: AgentReplacementServing {
  let log: ReplacementCallLog
  let ticket: ServiceReplacementTicket

  var descriptorResult: Result<ServiceDescriptor, Error> = .failure(TestError.expected)
  var statusResult: Result<Bool, Error> = .success(false)
  var prepareError: Error?
  var commitError: Error?
  var unlockError: Error?

  private(set) var prepareCalls: [(unlockIfNeeded: Bool, expectedAgentInstanceID: UUID)] = []
  private(set) var committedTickets: [ServiceReplacementTicket] = []
  private(set) var cancelledTickets: [ServiceReplacementTicket] = []
  private(set) var descriptorCallCount = 0
  private(set) var resetConnectionCallCount = 0
  private(set) var statusCallCount = 0
  private(set) var unlockCallCount = 0

  init(log: ReplacementCallLog, ticket: ServiceReplacementTicket) {
    self.log = log
    self.ticket = ticket
  }

  func serviceDescriptor() async throws -> ServiceDescriptor {
    log.record(.serviceDescriptor)
    descriptorCallCount += 1
    return try descriptorResult.get()
  }

  func unlock() async throws {
    log.record(.unlock)
    unlockCallCount += 1
    if let unlockError {
      throw unlockError
    }
  }

  func status() async throws -> Bool {
    log.record(.status)
    statusCallCount += 1
    return try statusResult.get()
  }

  func prepareForReplacement(
    unlockIfNeeded: Bool,
    expectedAgentInstanceID: UUID
  ) async throws -> ServiceReplacementTicket {
    log.record(.prepare)
    prepareCalls.append((unlockIfNeeded, expectedAgentInstanceID))
    if let prepareError {
      throw prepareError
    }
    return ticket
  }

  func cancelReplacementPreparation(
    ticket: ServiceReplacementTicket
  ) async throws {
    log.record(.cancel)
    cancelledTickets.append(ticket)
  }

  func commitReplacement(
    ticket: ServiceReplacementTicket
  ) async throws {
    log.record(.commit)
    if let commitError {
      throw commitError
    }
    committedTickets.append(ticket)
  }

  func resetConnection() {
    log.record(.resetConnection)
    resetConnectionCallCount += 1
  }
}

@MainActor
private final class FakeAgentReplacementLifecycle: AgentReplacementLifecycleServing {
  let log: ReplacementCallLog
  var restartResult: AgentRegistrar.State = .enabled

  init(log: ReplacementCallLog) {
    self.log = log
  }

  func restart() async -> AgentRegistrar.State {
    log.record(.restart)
    return restartResult
  }
}

private func makeDescriptor(
  agentInstanceID: UUID = UUID(),
  replacementPending: Bool = false
) -> ServiceDescriptor {
  ServiceDescriptor(
    protocolVersion: ServiceContract.protocolVersion,
    capabilities: ServiceContract.requiredCapabilities,
    agentBundleIdentifier: SharedConstants.agentBundleIdentifier,
    agentVersion: "1.0",
    agentBuild: "1",
    agentInstanceID: agentInstanceID,
    replacementPending: replacementPending
  )
}

private enum TestError: Error, Equatable {
  case expected
}
