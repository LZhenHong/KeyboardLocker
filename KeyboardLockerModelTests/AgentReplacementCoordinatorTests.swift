import Client
import Foundation
import Testing

@Suite(.serialized)
struct AgentReplacementCoordinatorTests {
  @Test
  @MainActor
  func safePlanPreparesAndCommitsBeforeRestarting() async {
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

    #expect(log.steps == [.prepare, .commit, .restart, .resetConnection])
    #expect(client.prepareCalls.count == 1)
    #expect(client.prepareCalls.first?.unlockIfNeeded == true)
    #expect(
      client.prepareCalls.first?.expectedAgentInstanceID ==
        descriptor.agentInstanceID
    )
    #expect(client.committedTickets == [ticket])
    #expect(client.cancelledTickets.isEmpty)
  }

  @Test
  @MainActor
  func safePlanRestartSuccessReturnsRestartedAndResetsConnection() async {
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
      Issue.record("Expected .restarted, got \(outcome).")
      return
    }
    #expect(previousAgentInstanceID == descriptor.agentInstanceID)
    #expect(client.resetConnectionCallCount == 1)
  }

  @Test
  @MainActor
  func committedSafePlanRestartFailureDoesNotCancelPreparation() async {
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
      Issue.record("Expected .registration, got \(outcome).")
      return
    }
    #expect(state == .approvalRequired)
    #expect(client.committedTickets == [ticket])
    #expect(client.cancelledTickets.isEmpty)
    #expect(client.resetConnectionCallCount == 1)
    #expect(log.steps == [.prepare, .commit, .restart, .resetConnection])
  }

  @Test
  @MainActor
  func prepareFailureReportsFailedWithCurrentLockState() async {
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
      Issue.record("Expected .failed, got \(outcome).")
      return
    }
    #expect(error as? TestError == .expected)
    #expect(currentLockState == true)
    #expect(client.cancelledTickets.isEmpty)
    #expect(client.statusCallCount == 1)
    #expect(log.steps == [.prepare, .serviceDescriptor, .status])
  }

  @Test
  @MainActor
  func commitFailureCancelsPreparedTicketThenReportsFailed() async {
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
      Issue.record("Expected .failed, got \(outcome).")
      return
    }
    #expect(error as? TestError == .expected)
    #expect(currentLockState == false)
    #expect(client.cancelledTickets == [ticket])
    #expect(client.committedTickets.isEmpty)
    #expect(
      log.steps ==
        [.prepare, .commit, .cancel, .serviceDescriptor, .status]
    )
  }

  @Test
  @MainActor
  func safePlanFailureRedetectsTrustedReplacementInProgress() async {
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
      Issue.record("Expected .replacementInProgress, got \(outcome).")
      return
    }
    #expect(reported == pendingDescriptor)
    #expect(client.cancelledTickets == [ticket])
    #expect(client.statusCallCount == 0)
  }

  @Test
  @MainActor
  func forcedPlanFailureDoesNotRedetectReplacementInProgress() async {
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
      Issue.record("Expected .failed, got \(outcome).")
      return
    }
    #expect(error as? TestError == .expected)
    #expect(currentLockState == true)
    #expect(client.descriptorCallCount == 0)
    #expect(log.steps == [.unlock, .status])
  }

  @Test
  @MainActor
  func forcedPlanWithKnownLockStateUnlocksBeforeRestarting() async {
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
      Issue.record("Expected .restarted, got \(outcome).")
      return
    }
    #expect(previousAgentInstanceID == descriptor.agentInstanceID)
    #expect(client.unlockCallCount == 1)
    #expect(client.prepareCalls.isEmpty)
    #expect(client.committedTickets.isEmpty)
    #expect(client.cancelledTickets.isEmpty)
    #expect(log.steps == [.unlock, .restart, .resetConnection])
  }

  @Test
  @MainActor
  func forcedPlanWithKnownLockStateRestartFailureReturnsRegistration() async {
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
      Issue.record("Expected .registration, got \(outcome).")
      return
    }
    #expect(state == .approvalRequired)
    #expect(client.unlockCallCount == 1)
    #expect(client.cancelledTickets.isEmpty)
    #expect(log.steps == [.unlock, .restart, .resetConnection])
  }

  @Test
  @MainActor
  func forcedPlanWithUnknownLockStateSkipsUnlock() async {
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
      Issue.record("Expected .restarted, got \(outcome).")
      return
    }
    #expect(previousAgentInstanceID == nil)
    #expect(client.unlockCallCount == 0)
    #expect(client.statusCallCount == 0)
    #expect(log.steps == [.restart, .resetConnection])
  }

  @Test
  @MainActor
  func forcedPlanRestartFailureReturnsRegistration() async {
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
      Issue.record("Expected .registration, got \(outcome).")
      return
    }
    #expect(state == .unavailable(.restartFailed("Restart failed for testing.")))
    #expect(client.resetConnectionCallCount == 1)
    #expect(log.steps == [.restart, .resetConnection])
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
