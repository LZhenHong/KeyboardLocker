import Client
import Foundation
import XCTest

final class AgentReadinessCoordinatorTests: XCTestCase {
  @MainActor
  func testNonEnabledRegistrationSkipsXPCAndReturnsRegistration() async {
    let client = FakeAgentReadinessClient(
      descriptorResults: [.failure(TestError.handshake)]
    )
    let lifecycle = FakeAgentReadinessLifecycle(
      ensureEnabledResult: .approvalRequired
    )
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .registration(state) = outcome else {
      XCTFail("Expected .registration, got \(outcome).")
      return
    }
    XCTAssertEqual(state, .approvalRequired)
    XCTAssertEqual(client.descriptorCallCount, 0)
    XCTAssertEqual(client.statusCallCount, 0)
    XCTAssertEqual(client.resetConnectionCallCount, 0)
    XCTAssertTrue(lifecycle.checkedDescriptors.isEmpty)
  }

  @MainActor
  func testHandshakeFailureResetsConnectionOnceAndRetries() async {
    let descriptor = makeDescriptor()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.failure(TestError.handshake), .success(descriptor)],
      statusResult: .success(true),
      permissionResult: .success(true)
    )
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .ready(isLocked, hasAccessibilityPermission) = outcome else {
      XCTFail("Expected .ready, got \(outcome).")
      return
    }
    XCTAssertTrue(isLocked)
    XCTAssertTrue(hasAccessibilityPermission)
    XCTAssertEqual(client.descriptorCallCount, 2)
    XCTAssertEqual(client.resetConnectionCallCount, 1)
    XCTAssertEqual(
      Array(client.events.prefix(3)),
      [.serviceDescriptor, .resetConnection, .serviceDescriptor]
    )
  }

  @MainActor
  func testDoubleHandshakeFailureFallsBackToForcedUpdateWithStatusLockState() async {
    let client = FakeAgentReadinessClient(
      descriptorResults: [
        .failure(TestError.handshake),
        .failure(TestError.handshake),
      ],
      statusResult: .success(true)
    )
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .updateRequired(plan) = outcome else {
      XCTFail("Expected .updateRequired, got \(outcome).")
      return
    }
    guard case let .forced(descriptor, isLocked) = plan.mode else {
      XCTFail("Expected a forced plan, got \(plan.mode).")
      return
    }
    XCTAssertNil(descriptor)
    XCTAssertEqual(isLocked, true)
    XCTAssertTrue(plan.message.contains("could not be verified"))
    XCTAssertEqual(client.descriptorCallCount, 2)
    XCTAssertEqual(client.statusCallCount, 1)
    XCTAssertEqual(client.resetConnectionCallCount, 2)
    XCTAssertTrue(lifecycle.checkedDescriptors.isEmpty)
  }

  @MainActor
  func testDoubleHandshakeFailureWithUnreadableStatusReportsHandshakeContext() async {
    let client = FakeAgentReadinessClient(
      descriptorResults: [
        .failure(TestError.handshake),
        .failure(TestError.handshake),
      ],
      statusResult: .failure(TestError.status)
    )
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .failure(error, context) = outcome else {
      XCTFail("Expected .failure, got \(outcome).")
      return
    }
    XCTAssertEqual(error as? TestError, .status)
    XCTAssertTrue(context?.contains("Descriptor handshake failed") == true)
  }

  @MainActor
  func testCompatibleDescriptorReturnsReadySnapshot() async {
    let descriptor = makeDescriptor()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)],
      statusResult: .success(false),
      permissionResult: .success(true)
    )
    let lifecycle = FakeAgentReadinessLifecycle(compatibilityResult: .compatible)
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .ready(isLocked, hasAccessibilityPermission) = outcome else {
      XCTFail("Expected .ready, got \(outcome).")
      return
    }
    XCTAssertFalse(isLocked)
    XCTAssertTrue(hasAccessibilityPermission)
    XCTAssertEqual(client.descriptorCallCount, 1)
    XCTAssertEqual(client.resetConnectionCallCount, 0)
    XCTAssertEqual(lifecycle.checkedDescriptors, [descriptor])
  }

  @MainActor
  func testMatchingPreviousInstanceIDReportsAgentDidNotRestart() async {
    let instanceID = UUID()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(makeDescriptor(agentInstanceID: instanceID))]
    )
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect(
      expectedPreviousAgentInstanceID: instanceID
    )

    guard case .agentDidNotRestart = outcome else {
      XCTFail("Expected .agentDidNotRestart, got \(outcome).")
      return
    }
    XCTAssertTrue(lifecycle.checkedDescriptors.isEmpty)
    XCTAssertEqual(client.statusCallCount, 0)
  }

  @MainActor
  func testBundledUpgradeAvailableCarriesDescriptorMessageBuildAndLockState() async {
    let descriptor = makeDescriptor()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)],
      statusResult: .success(true)
    )
    let lifecycle = FakeAgentReadinessLifecycle(
      compatibilityResult: .bundledAgentUpgradeAvailable(
        message: "Upgrade available.",
        bundledBuild: "99"
      )
    )
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .updateAvailable(
      reportedDescriptor,
      message,
      bundledBuild,
      isLocked
    ) = outcome else {
      XCTFail("Expected .updateAvailable, got \(outcome).")
      return
    }
    XCTAssertEqual(reportedDescriptor, descriptor)
    XCTAssertEqual(message, "Upgrade available.")
    XCTAssertEqual(bundledBuild, "99")
    XCTAssertTrue(isLocked)
    XCTAssertEqual(client.statusCallCount, 1)
  }

  @MainActor
  func testSafeReplacementWithoutReadableLockStateFails() async {
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(makeDescriptor())]
    )
    let lifecycle = FakeAgentReadinessLifecycle(
      compatibilityResult: .updateRequired(
        message: "Update required.",
        canReadLockState: false,
        supportsSafeReplacement: true
      )
    )
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .failure(error, context) = outcome else {
      XCTFail("Expected .failure, got \(outcome).")
      return
    }
    XCTAssertEqual(
      error.localizedDescription,
      "Safe KeyboardLocker agent replacement requires a readable authoritative lock state."
    )
    XCTAssertNil(context)
    XCTAssertEqual(client.statusCallCount, 0)
  }

  @MainActor
  func testUpdateRequiredWithoutLockStateOrSafeSupportForcesUpdate() async {
    let descriptor = makeDescriptor()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)]
    )
    let lifecycle = FakeAgentReadinessLifecycle(
      compatibilityResult: .updateRequired(
        message: "Update required.",
        canReadLockState: false,
        supportsSafeReplacement: false
      )
    )
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .updateRequired(plan) = outcome else {
      XCTFail("Expected .updateRequired, got \(outcome).")
      return
    }
    XCTAssertEqual(
      plan,
      AgentUpdatePlan(
        mode: .forced(descriptor: descriptor, isLocked: nil),
        message: "Update required."
      )
    )
    XCTAssertEqual(client.statusCallCount, 0)
  }

  @MainActor
  func testUpdateRequiredWithLockStateAndSafeSupportChoosesSafeMode() async {
    let descriptor = makeDescriptor()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)],
      statusResult: .success(true)
    )
    let lifecycle = FakeAgentReadinessLifecycle(
      compatibilityResult: .updateRequired(
        message: "Update required.",
        canReadLockState: true,
        supportsSafeReplacement: true
      )
    )
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .updateRequired(plan) = outcome else {
      XCTFail("Expected .updateRequired, got \(outcome).")
      return
    }
    XCTAssertEqual(
      plan,
      AgentUpdatePlan(
        mode: .safe(descriptor: descriptor, isLocked: true),
        message: "Update required."
      )
    )
    XCTAssertEqual(client.statusCallCount, 1)
  }

  @MainActor
  func testUpdateRequiredWithLockStateWithoutSafeSupportChoosesForcedMode() async {
    let descriptor = makeDescriptor()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)],
      statusResult: .success(false)
    )
    let lifecycle = FakeAgentReadinessLifecycle(
      compatibilityResult: .updateRequired(
        message: "Update required.",
        canReadLockState: true,
        supportsSafeReplacement: false
      )
    )
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .updateRequired(plan) = outcome else {
      XCTFail("Expected .updateRequired, got \(outcome).")
      return
    }
    XCTAssertEqual(
      plan,
      AgentUpdatePlan(
        mode: .forced(descriptor: descriptor, isLocked: false),
        message: "Update required."
      )
    )
    XCTAssertEqual(client.statusCallCount, 1)
  }

  @MainActor
  func testTrustedReplacementInProgressShortCircuitsCompatibilityOutcome() async {
    let descriptor = makeDescriptor(replacementPending: true)
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)]
    )
    let lifecycle = FakeAgentReadinessLifecycle(compatibilityResult: .compatible)
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .replacementInProgress(reported) = outcome else {
      XCTFail("Expected .replacementInProgress, got \(outcome).")
      return
    }
    XCTAssertEqual(reported, descriptor)
    XCTAssertEqual(client.statusCallCount, 0)
  }

  @MainActor
  func testReplacementPendingWithWrongBundleIdentifierFallsThroughToCompatibility() async {
    let descriptor = makeDescriptor(
      agentBundleIdentifier: "com.example.unrelated.agent",
      replacementPending: true
    )
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)]
    )
    let lifecycle = FakeAgentReadinessLifecycle(compatibilityResult: .compatible)
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case .ready = outcome else {
      XCTFail("Expected .ready, got \(outcome).")
      return
    }
    XCTAssertEqual(client.statusCallCount, 1)
  }

  @MainActor
  func testReplacementPendingWithoutDrainCapabilityFallsThroughToCompatibility() async {
    var capabilities = ServiceContract.requiredCapabilities
    capabilities.remove(.committedReplacementDrain)
    let descriptor = makeDescriptor(
      capabilities: capabilities,
      replacementPending: true
    )
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)]
    )
    let lifecycle = FakeAgentReadinessLifecycle(compatibilityResult: .compatible)
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case .ready = outcome else {
      XCTFail("Expected .ready, got \(outcome).")
      return
    }
    XCTAssertEqual(client.statusCallCount, 1)
  }

  @MainActor
  func testReplacementPendingWithInvalidBundleCompatibilityFallsThrough() async {
    let descriptor = makeDescriptor(replacementPending: true)
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)]
    )
    let lifecycle = FakeAgentReadinessLifecycle(
      compatibilityResult: .invalidBundle(.invalidBundle("Corrupt bundle."))
    )
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .invalidBundle(failure) = outcome else {
      XCTFail("Expected .invalidBundle, got \(outcome).")
      return
    }
    XCTAssertEqual(failure, .invalidBundle("Corrupt bundle."))
    XCTAssertEqual(client.statusCallCount, 0)
  }

  @MainActor
  func testCancellationAfterEnsureEnabledReturnsCancelled() async {
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(makeDescriptor())]
    )
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    inspection.cancel()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      XCTFail("Expected .cancelled, got \(outcome).")
      return
    }
    XCTAssertEqual(client.descriptorCallCount, 0)
  }

  @MainActor
  func testCancellationDuringInitialDescriptorFetchReturnsCancelled() async {
    let descriptorGate = ReadinessTestGate()
    let descriptorStarted = expectation(description: "Descriptor fetch started.")
    descriptorGate.onEntered = { descriptorStarted.fulfill() }
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(makeDescriptor())]
    )
    client.descriptorGate = descriptorGate
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    await fulfillment(of: [descriptorStarted], timeout: 5)
    inspection.cancel()
    descriptorGate.open()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      XCTFail("Expected .cancelled, got \(outcome).")
      return
    }
    XCTAssertEqual(client.descriptorCallCount, 1)
    XCTAssertTrue(lifecycle.checkedDescriptors.isEmpty)
  }

  @MainActor
  func testCancellationAfterDescriptorFailureSkipsRetryAndReturnsCancelled() async {
    let descriptorGate = ReadinessTestGate()
    let descriptorStarted = expectation(description: "Descriptor fetch started.")
    descriptorGate.onEntered = { descriptorStarted.fulfill() }
    let client = FakeAgentReadinessClient(
      descriptorResults: [.failure(TestError.handshake)]
    )
    client.descriptorGate = descriptorGate
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    await fulfillment(of: [descriptorStarted], timeout: 5)
    inspection.cancel()
    descriptorGate.open()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      XCTFail("Expected .cancelled, got \(outcome).")
      return
    }
    XCTAssertEqual(client.descriptorCallCount, 1)
    XCTAssertEqual(client.resetConnectionCallCount, 0)
  }

  @MainActor
  func testCancellationDuringCompatibleStatusFetchReturnsCancelled() async {
    let statusGate = ReadinessTestGate()
    let statusStarted = expectation(description: "Status fetch started.")
    statusGate.onEntered = { statusStarted.fulfill() }
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(makeDescriptor())],
      statusResult: .success(true)
    )
    client.statusGate = statusGate
    let lifecycle = FakeAgentReadinessLifecycle(compatibilityResult: .compatible)
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    await fulfillment(of: [statusStarted], timeout: 5)
    inspection.cancel()
    statusGate.open()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      XCTFail("Expected .cancelled, got \(outcome).")
      return
    }
    XCTAssertEqual(client.statusCallCount, 1)
  }

  @MainActor
  func testCancellationDuringUnverifiedAgentStatusFetchReturnsCancelled() async {
    let statusGate = ReadinessTestGate()
    let statusStarted = expectation(description: "Status fetch started.")
    statusGate.onEntered = { statusStarted.fulfill() }
    let client = FakeAgentReadinessClient(
      descriptorResults: [
        .failure(TestError.handshake),
        .failure(TestError.handshake),
      ],
      statusResult: .success(true)
    )
    client.statusGate = statusGate
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    await fulfillment(of: [statusStarted], timeout: 5)
    inspection.cancel()
    statusGate.open()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      XCTFail("Expected .cancelled, got \(outcome).")
      return
    }
    XCTAssertEqual(client.descriptorCallCount, 2)
    XCTAssertEqual(client.statusCallCount, 1)
  }
}

@MainActor
private final class FakeAgentReadinessClient: AgentReadinessServing {
  enum Event: Equatable {
    case hasAccessibilityPermission
    case resetConnection
    case serviceDescriptor
    case status
  }

  private var descriptorResults: [Result<ServiceDescriptor, Error>]
  var statusResult: Result<Bool, Error>
  var permissionResult: Result<Bool, Error>
  var descriptorGate: ReadinessTestGate?
  var statusGate: ReadinessTestGate?

  private(set) var events: [Event] = []
  private(set) var descriptorCallCount = 0
  private(set) var statusCallCount = 0
  private(set) var resetConnectionCallCount = 0

  init(
    descriptorResults: [Result<ServiceDescriptor, Error>],
    statusResult: Result<Bool, Error> = .success(false),
    permissionResult: Result<Bool, Error> = .success(true)
  ) {
    precondition(
      !descriptorResults.isEmpty,
      "At least one scripted descriptor result is required."
    )
    self.descriptorResults = descriptorResults
    self.statusResult = statusResult
    self.permissionResult = permissionResult
  }

  func serviceDescriptor() async throws -> ServiceDescriptor {
    events.append(.serviceDescriptor)
    descriptorCallCount += 1
    if let descriptorGate {
      await descriptorGate.wait()
    }
    let result = descriptorResults.count > 1
      ? descriptorResults.removeFirst()
      : descriptorResults[0]
    return try result.get()
  }

  func status() async throws -> Bool {
    events.append(.status)
    statusCallCount += 1
    if let statusGate {
      await statusGate.wait()
    }
    return try statusResult.get()
  }

  func hasAccessibilityPermission() async throws -> Bool {
    events.append(.hasAccessibilityPermission)
    return try permissionResult.get()
  }

  func resetConnection() {
    events.append(.resetConnection)
    resetConnectionCallCount += 1
  }
}

@MainActor
private final class FakeAgentReadinessLifecycle: AgentReadinessLifecycleServing {
  var ensureEnabledResult: AgentRegistrar.State
  var compatibilityResult: AgentRegistrar.Compatibility
  private(set) var checkedDescriptors: [ServiceDescriptor] = []

  init(
    ensureEnabledResult: AgentRegistrar.State = .enabled,
    compatibilityResult: AgentRegistrar.Compatibility = .compatible
  ) {
    self.ensureEnabledResult = ensureEnabledResult
    self.compatibilityResult = compatibilityResult
  }

  func ensureEnabled() -> AgentRegistrar.State {
    ensureEnabledResult
  }

  func compatibility(
    of descriptor: ServiceDescriptor
  ) -> AgentRegistrar.Compatibility {
    checkedDescriptors.append(descriptor)
    return compatibilityResult
  }
}

/// Holds a fake XPC response until the test releases it, so cancellation can land while
/// the coordinator is suspended at a specific call.
@MainActor
private final class ReadinessTestGate {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var isOpen = false

  var onEntered: (() -> Void)?

  func wait() async {
    onEntered?()
    guard !isOpen else {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume() }
  }
}

private func makeDescriptor(
  agentInstanceID: UUID = UUID(),
  capabilities: Set<ServiceCapability> = ServiceContract.requiredCapabilities,
  agentBundleIdentifier: String = SharedConstants.agentBundleIdentifier,
  replacementPending: Bool = false
) -> ServiceDescriptor {
  ServiceDescriptor(
    protocolVersion: ServiceContract.protocolVersion,
    capabilities: capabilities,
    agentBundleIdentifier: agentBundleIdentifier,
    agentVersion: "1.0",
    agentBuild: "1",
    agentInstanceID: agentInstanceID,
    replacementPending: replacementPending
  )
}

private enum TestError: Error, Equatable {
  case handshake
  case status
}
