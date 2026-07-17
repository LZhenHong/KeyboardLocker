import Client
import XCTest

final class ExternalAutomationControllerTests: XCTestCase {
  @MainActor
  func testLockInvokesOnlyLockCapability() async {
    let client = RecordingExternalAutomationClient(isLocked: false)
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(.lock, source: .service)
    await controller.waitUntilIdle()

    XCTAssertEqual(client.calls, [.lock])
    XCTAssertTrue(client.isLocked)
    XCTAssertTrue(presenter.statuses.isEmpty)
    XCTAssertTrue(presenter.failureBatches.isEmpty)
  }

  @MainActor
  func testUnlockInvokesOnlyUnlockCapability() async {
    let client = RecordingExternalAutomationClient(isLocked: true)
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(.unlock, source: .service)
    await controller.waitUntilIdle()

    XCTAssertEqual(client.calls, [.unlock])
    XCTAssertFalse(client.isLocked)
  }

  @MainActor
  func testStatusPresentsAuthoritativeAgentValue() async {
    let client = RecordingExternalAutomationClient(isLocked: true)
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(.status, source: .service)
    await controller.waitUntilIdle()

    XCTAssertEqual(client.calls, [.status])
    XCTAssertEqual(presenter.statuses, [.init(isLocked: true, source: .service)])
    XCTAssertTrue(presenter.failureBatches.isEmpty)
  }

  @MainActor
  func testAgentFailureIncludesRecoverySuggestion() async {
    let client = RecordingExternalAutomationClient(
      isLocked: false,
      error: XPCClientError.serviceUnavailable
    )
    let presenter = RecordingExternalAutomationPresenter()
    let controller = ExternalAutomationController(client: client, presenter: presenter)

    controller.submit(.lock, source: .service)
    await controller.waitUntilIdle()

    let batch = presenter.failureBatches.first
    XCTAssertEqual(batch?.source, .service)
    XCTAssertTrue(batch?.failures.first?.message.contains("not reachable") == true)
    XCTAssertTrue(batch?.failures.first?.message.contains("Open KeyboardLocker once") == true)
  }

  @MainActor
  func testBatchPreservesDesiredStateOrder() async {
    let client = RecordingExternalAutomationClient(isLocked: false)
    let controller = ExternalAutomationController(
      client: client,
      presenter: RecordingExternalAutomationPresenter()
    )

    controller.submit([.lock, .status, .unlock], source: .urlScheme)
    await controller.waitUntilIdle()

    XCTAssertEqual(client.calls, [.lock, .status, .unlock])
    XCTAssertFalse(client.isLocked)
  }

  @MainActor
  func testSeparateSubmissionsStaySerializedWhileFirstActionIsSuspended() async {
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

    XCTAssertEqual(client.calls, [.lock])

    await gate.open()
    await controller.waitUntilIdle()

    XCTAssertEqual(client.calls, [.lock, .unlock])
    XCTAssertFalse(client.isLocked)
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
