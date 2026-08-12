import Client
import Testing

@Suite(.serialized)
struct ExternalAutomationControllerTests {
  @Test
  @MainActor
  func lockInvokesOnlyLockCapability() async {
    let client = RecordingExternalAutomationClient(isLocked: false)
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(.lock, source: .service)
    await controller.waitUntilIdle()

    #expect(client.calls == [.lock])
    #expect(client.isLocked)
    #expect(presenter.statuses.isEmpty)
    #expect(presenter.failureBatches.isEmpty)
  }

  @Test
  @MainActor
  func unlockInvokesOnlyUnlockCapability() async {
    let client = RecordingExternalAutomationClient(isLocked: true)
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(.unlock, source: .service)
    await controller.waitUntilIdle()

    #expect(client.calls == [.unlock])
    #expect(!client.isLocked)
  }

  @Test
  @MainActor
  func statusPresentsAuthoritativeAgentValue() async {
    let client = RecordingExternalAutomationClient(isLocked: true)
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(.status, source: .service)
    await controller.waitUntilIdle()

    #expect(client.calls == [.status])
    #expect(presenter.statuses == [.init(isLocked: true, source: .service)])
    #expect(presenter.failureBatches.isEmpty)
  }

  @Test
  @MainActor
  func agentFailureIncludesRecoverySuggestion() async {
    let client = RecordingExternalAutomationClient(
      isLocked: false,
      error: XPCClientError.serviceUnavailable
    )
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(.lock, source: .service)
    await controller.waitUntilIdle()

    let batch = presenter.failureBatches.first
    #expect(batch?.source == .service)
    #expect(batch?.failures.first?.message.contains("not reachable") == true)
    #expect(batch?.failures.first?.message.contains("Open KeyboardLocker once") == true)
  }

  @Test
  @MainActor
  func batchPreservesDesiredStateOrder() async {
    let client = RecordingExternalAutomationClient(isLocked: false)
    let controller = ExternalAutomationController(
      client: client,
      presenter: RecordingExternalAutomationPresenter()
    )

    controller.submit([.lock, .status, .unlock], source: .urlScheme)
    await controller.waitUntilIdle()

    #expect(client.calls == [.lock, .status, .unlock])
    #expect(!client.isLocked)
  }

  @Test
  @MainActor
  func rejectedRequestIsPresentedWithoutCallingAgent() async {
    let client = RecordingExternalAutomationClient(isLocked: false)
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(
      [.failure(.init(message: "Invalid URL"))],
      source: .urlScheme
    )
    await controller.waitUntilIdle()

    #expect(client.calls.isEmpty)
    #expect(
      presenter.failureBatches ==
        [.init(failures: [.init(message: "Invalid URL")], source: .urlScheme)]
    )
  }

  @Test
  @MainActor
  func separateSubmissionsStaySerializedWhileFirstActionIsSuspended() async {
    let gate = AsyncGate()
    let client = RecordingExternalAutomationClient(isLocked: false, lockGate: gate)
    let controller = ExternalAutomationController(
      client: client,
      presenter: RecordingExternalAutomationPresenter()
    )

    controller.submit(.lock, source: .service)
    await gate.waitUntilEntered()
    controller.submit(.unlock, source: .service)
    await Task.yield()

    #expect(client.calls == [.lock])

    await gate.open()
    await controller.waitUntilIdle()

    #expect(client.calls == [.lock, .unlock])
    #expect(!client.isLocked)
  }

  @Test
  @MainActor
  func submitAndWaitReturnsNilWhenActionSucceeds() async {
    let client = RecordingExternalAutomationClient(isLocked: false)
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    let failure = await controller.submitAndWait(.lock, source: .service)

    #expect(failure == nil)
    #expect(client.calls == [.lock])
    #expect(client.isLocked)
    #expect(presenter.failureBatches.isEmpty)
  }

  @Test
  @MainActor
  func submitAndWaitReturnsFailureWithoutPresentingIt() async {
    let client = RecordingExternalAutomationClient(
      isLocked: false,
      error: XPCClientError.serviceUnavailable
    )
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    let failure = await controller.submitAndWait(.lock, source: .service)

    #expect(failure?.message.contains("not reachable") == true)
    #expect(presenter.failureBatches.isEmpty)
  }

  @Test
  @MainActor
  func submitAndWaitStaysSerializedBehindPendingSubmission() async {
    let gate = AsyncGate()
    let client = RecordingExternalAutomationClient(isLocked: false, lockGate: gate)
    let controller = ExternalAutomationController(
      client: client,
      presenter: RecordingExternalAutomationPresenter()
    )

    controller.submit(.lock, source: .service)
    await gate.waitUntilEntered()

    async let awaitedFailure = controller.submitAndWait(.unlock, source: .service)
    await Task.yield()

    #expect(client.calls == [.lock])

    await gate.open()
    let failure = await awaitedFailure

    #expect(failure == nil)
    #expect(client.calls == [.lock, .unlock])
    #expect(!client.isLocked)
  }
}

@MainActor
private final class RecordingExternalAutomationClient: AgentLockActionServing {
  private(set) var calls: [ExternalAutomationAction] = []
  private(set) var isLocked: Bool

  private let error: Error?
  private let lockGate: AsyncGate?

  init(
    isLocked: Bool,
    error: Error? = nil,
    lockGate: AsyncGate? = nil
  ) {
    self.isLocked = isLocked
    self.error = error
    self.lockGate = lockGate
  }

  func lock() async throws {
    calls.append(.lock)
    if let lockGate {
      await lockGate.enterAndWait()
    }
    try throwConfiguredError()
    isLocked = true
  }

  func unlock() async throws {
    calls.append(.unlock)
    try throwConfiguredError()
    isLocked = false
  }

  func status() async throws -> Bool {
    calls.append(.status)
    try throwConfiguredError()
    return isLocked
  }

  func toggle() async throws -> Bool {
    try throwConfiguredError()
    isLocked.toggle()
    return isLocked
  }

  private func throwConfiguredError() throws {
    if let error {
      throw error
    }
  }
}

@MainActor
private final class RecordingExternalAutomationPresenter: ExternalAutomationPresenting {
  struct Status: Equatable {
    let isLocked: Bool
    let source: ExternalAutomationSource
  }

  struct FailureBatch: Equatable {
    let failures: [ExternalAutomationFailure]
    let source: ExternalAutomationSource
  }

  private(set) var statuses: [Status] = []
  private(set) var failureBatches: [FailureBatch] = []

  func presentStatus(isLocked: Bool, source: ExternalAutomationSource) {
    statuses.append(.init(isLocked: isLocked, source: source))
  }

  func presentFailures(
    _ failures: [ExternalAutomationFailure],
    source: ExternalAutomationSource
  ) {
    failureBatches.append(.init(failures: failures, source: source))
  }
}

private actor AsyncGate {
  private var entered = false
  private var isOpen = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var openWaiters: [CheckedContinuation<Void, Never>] = []

  func enterAndWait() async {
    entered = true
    entryWaiters.forEach { $0.resume() }
    entryWaiters.removeAll()

    guard !isOpen else {
      return
    }

    await withCheckedContinuation { continuation in
      openWaiters.append(continuation)
    }
  }

  func waitUntilEntered() async {
    guard !entered else {
      return
    }

    await withCheckedContinuation { continuation in
      entryWaiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    openWaiters.forEach { $0.resume() }
    openWaiters.removeAll()
  }
}
