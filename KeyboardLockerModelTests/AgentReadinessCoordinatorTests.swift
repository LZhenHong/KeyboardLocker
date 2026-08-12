import Client
import Foundation
import Testing

@Suite(.serialized)
struct AgentReadinessCoordinatorTests {
  @MainActor
  @Test
  func nonEnabledRegistrationSkipsXPCAndReturnsRegistration() async {
    let client = FakeAgentReadinessClient(
      descriptorResults: [.failure(TestError.handshake)]
    )
    let lifecycle = FakeAgentReadinessLifecycle(
      ensureEnabledResult: .approvalRequired
    )
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .registration(state) = outcome else {
      Issue.record("Expected .registration, got \(outcome).")
      return
    }
    #expect(state == .approvalRequired)
    #expect(client.descriptorCallCount == 0)
    #expect(client.statusCallCount == 0)
    #expect(client.resetConnectionCallCount == 0)
    #expect(lifecycle.checkedDescriptors.isEmpty)
  }

  @MainActor
  @Test
  func handshakeFailureResetsConnectionOnceAndRetries() async {
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
      Issue.record("Expected .ready, got \(outcome).")
      return
    }
    #expect(isLocked)
    #expect(hasAccessibilityPermission)
    #expect(client.descriptorCallCount == 2)
    #expect(client.resetConnectionCallCount == 1)
    #expect(Array(client.events.prefix(3)) == [.serviceDescriptor, .resetConnection, .serviceDescriptor])
  }

  @MainActor
  @Test
  func doubleHandshakeFailureFallsBackToForcedUpdateWithStatusLockState() async {
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
      Issue.record("Expected .updateRequired, got \(outcome).")
      return
    }
    guard case let .forced(descriptor, isLocked) = plan.mode else {
      Issue.record("Expected a forced plan, got \(plan.mode).")
      return
    }
    #expect(descriptor == nil)
    #expect(isLocked == true)
    #expect(plan.message.contains("could not be verified"))
    #expect(client.descriptorCallCount == 2)
    #expect(client.statusCallCount == 1)
    #expect(client.resetConnectionCallCount == 2)
    #expect(lifecycle.checkedDescriptors.isEmpty)
  }

  @MainActor
  @Test
  func doubleHandshakeFailureWithUnreadableStatusReportsHandshakeContext() async {
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
      Issue.record("Expected .failure, got \(outcome).")
      return
    }
    #expect(error as? TestError == .status)
    #expect(context?.contains("Descriptor handshake failed") == true)
  }

  @MainActor
  @Test
  func compatibleDescriptorReturnsReadySnapshot() async {
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
      Issue.record("Expected .ready, got \(outcome).")
      return
    }
    #expect(!isLocked)
    #expect(hasAccessibilityPermission)
    #expect(client.descriptorCallCount == 1)
    #expect(client.resetConnectionCallCount == 0)
    #expect(lifecycle.checkedDescriptors == [descriptor])
  }

  @MainActor
  @Test
  func matchingPreviousInstanceIDReportsAgentDidNotRestart() async {
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
      Issue.record("Expected .agentDidNotRestart, got \(outcome).")
      return
    }
    #expect(lifecycle.checkedDescriptors.isEmpty)
    #expect(client.statusCallCount == 0)
  }

  @MainActor
  @Test
  func bundledUpgradeAvailableCarriesDescriptorMessageBuildAndLockState() async {
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
      Issue.record("Expected .updateAvailable, got \(outcome).")
      return
    }
    #expect(reportedDescriptor == descriptor)
    #expect(message == "Upgrade available.")
    #expect(bundledBuild == "99")
    #expect(isLocked)
    #expect(client.statusCallCount == 1)
  }

  @MainActor
  @Test
  func safeReplacementWithoutReadableLockStateFails() async {
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
      Issue.record("Expected .failure, got \(outcome).")
      return
    }
    #expect(error.localizedDescription == "Safe KeyboardLocker agent replacement requires a readable authoritative lock state.")
    #expect(context == nil)
    #expect(client.statusCallCount == 0)
  }

  @MainActor
  @Test
  func updateRequiredWithoutLockStateOrSafeSupportForcesUpdate() async {
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
      Issue.record("Expected .updateRequired, got \(outcome).")
      return
    }
    #expect(plan == AgentUpdatePlan(
      mode: .forced(descriptor: descriptor, isLocked: nil),
      message: "Update required."
    ))
    #expect(client.statusCallCount == 0)
  }

  @MainActor
  @Test
  func updateRequiredWithLockStateAndSafeSupportChoosesSafeMode() async {
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
      Issue.record("Expected .updateRequired, got \(outcome).")
      return
    }
    #expect(plan == AgentUpdatePlan(
      mode: .safe(descriptor: descriptor, isLocked: true),
      message: "Update required."
    ))
    #expect(client.statusCallCount == 1)
  }

  @MainActor
  @Test
  func updateRequiredWithLockStateWithoutSafeSupportChoosesForcedMode() async {
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
      Issue.record("Expected .updateRequired, got \(outcome).")
      return
    }
    #expect(plan == AgentUpdatePlan(
      mode: .forced(descriptor: descriptor, isLocked: false),
      message: "Update required."
    ))
    #expect(client.statusCallCount == 1)
  }

  @MainActor
  @Test
  func trustedReplacementInProgressShortCircuitsCompatibilityOutcome() async {
    let descriptor = makeDescriptor(replacementPending: true)
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(descriptor)]
    )
    let lifecycle = FakeAgentReadinessLifecycle(compatibilityResult: .compatible)
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let outcome = await coordinator.inspect()

    guard case let .replacementInProgress(reported) = outcome else {
      Issue.record("Expected .replacementInProgress, got \(outcome).")
      return
    }
    #expect(reported == descriptor)
    #expect(client.statusCallCount == 0)
  }

  @MainActor
  @Test
  func replacementPendingWithWrongBundleIdentifierFallsThroughToCompatibility() async {
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
      Issue.record("Expected .ready, got \(outcome).")
      return
    }
    #expect(client.statusCallCount == 1)
  }

  @MainActor
  @Test
  func replacementPendingWithoutDrainCapabilityFallsThroughToCompatibility() async {
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
      Issue.record("Expected .ready, got \(outcome).")
      return
    }
    #expect(client.statusCallCount == 1)
  }

  @MainActor
  @Test
  func replacementPendingWithInvalidBundleCompatibilityFallsThrough() async {
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
      Issue.record("Expected .invalidBundle, got \(outcome).")
      return
    }
    #expect(failure == .invalidBundle("Corrupt bundle."))
    #expect(client.statusCallCount == 0)
  }

  @MainActor
  @Test
  func cancellationAfterEnsureEnabledReturnsCancelled() async {
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(makeDescriptor())]
    )
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    inspection.cancel()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      Issue.record("Expected .cancelled, got \(outcome).")
      return
    }
    #expect(client.descriptorCallCount == 0)
  }

  @MainActor
  @Test
  func cancellationDuringInitialDescriptorFetchReturnsCancelled() async {
    let descriptorGate = ReadinessTestGate()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(makeDescriptor())]
    )
    client.descriptorGate = descriptorGate
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    await descriptorGate.waitUntilEntered()
    inspection.cancel()
    descriptorGate.open()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      Issue.record("Expected .cancelled, got \(outcome).")
      return
    }
    #expect(client.descriptorCallCount == 1)
    #expect(lifecycle.checkedDescriptors.isEmpty)
  }

  @MainActor
  @Test
  func cancellationAfterDescriptorFailureSkipsRetryAndReturnsCancelled() async {
    let descriptorGate = ReadinessTestGate()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.failure(TestError.handshake)]
    )
    client.descriptorGate = descriptorGate
    let lifecycle = FakeAgentReadinessLifecycle()
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    await descriptorGate.waitUntilEntered()
    inspection.cancel()
    descriptorGate.open()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      Issue.record("Expected .cancelled, got \(outcome).")
      return
    }
    #expect(client.descriptorCallCount == 1)
    #expect(client.resetConnectionCallCount == 0)
  }

  @MainActor
  @Test
  func cancellationDuringCompatibleStatusFetchReturnsCancelled() async {
    let statusGate = ReadinessTestGate()
    let client = FakeAgentReadinessClient(
      descriptorResults: [.success(makeDescriptor())],
      statusResult: .success(true)
    )
    client.statusGate = statusGate
    let lifecycle = FakeAgentReadinessLifecycle(compatibilityResult: .compatible)
    let coordinator = AgentReadinessCoordinator(client: client, lifecycle: lifecycle)

    let inspection = Task { await coordinator.inspect() }
    await statusGate.waitUntilEntered()
    inspection.cancel()
    statusGate.open()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      Issue.record("Expected .cancelled, got \(outcome).")
      return
    }
    #expect(client.statusCallCount == 1)
  }

  @MainActor
  @Test
  func cancellationDuringUnverifiedAgentStatusFetchReturnsCancelled() async {
    let statusGate = ReadinessTestGate()
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
    await statusGate.waitUntilEntered()
    inspection.cancel()
    statusGate.open()
    let outcome = await inspection.value

    guard case .cancelled = outcome else {
      Issue.record("Expected .cancelled, got \(outcome).")
      return
    }
    #expect(client.descriptorCallCount == 2)
    #expect(client.statusCallCount == 1)
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
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var hasEntered = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var isOpen = false

  func wait() async {
    hasEntered = true
    let pendingEntryWaiters = entryWaiters
    entryWaiters.removeAll()
    pendingEntryWaiters.forEach { $0.resume() }
    guard !isOpen else {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func waitUntilEntered() async {
    guard !hasEntered else {
      return
    }
    await withCheckedContinuation { continuation in
      entryWaiters.append(continuation)
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
