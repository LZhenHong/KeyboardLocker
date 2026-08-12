import Client
import Foundation
import Testing

@Suite(.serialized)
struct AppCoordinatorTests {
  @Test
  func stateProjectsKnownLockEvidenceConsistently() {
    let cases: [(AppCoordinator.State, Bool?)] = [
      (.checking(lastKnownLock: true), true),
      (.checking(lastKnownLock: nil), nil),
      (.agentApprovalRequired, nil),
      (.agentReplacementInProgress(message: "Replacing"), nil),
      (.agentUpdateRequired(isLocked: false, message: "Update"), false),
      (.agentUpdateRequired(isLocked: nil, message: "Update"), nil),
      (.accessibilityRequired(isLocked: true), true),
      (.ready(isLocked: false), false),
      (.unavailable(message: "Unavailable", canRestartAgent: true), nil),
    ]

    for (state, expected) in cases {
      #expect(state.knownLockState == expected, "state: \(state)")
    }
  }

  @Test
  @MainActor
  func reconcilePublishesAuthoritativeReadySnapshot() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let lifecycle = FakeAgentLifecycle()
    let observer = FakeLockStateObserver()
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: lifecycle,
      observer: observer
    )
    var snapshots: [AppCoordinator.Snapshot] = []
    coordinator.onSnapshotChange = { snapshots.append($0) }

    coordinator.reconcile()
    try await waitUntil {
      coordinator.state == .ready(isLocked: false)
    }

    #expect(coordinator.snapshot == AppCoordinator.Snapshot(
      state: .ready(isLocked: false),
      activity: nil,
      lastError: nil,
      safetyCheckState: .idle
    ))
    #expect(observer.initialStates == [false])
    #expect(snapshots.last == coordinator.snapshot)
  }

  @Test
  @MainActor
  func displayedLockActionLocksThroughClientThenReconcilesAuthoritativeState() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let lifecycle = FakeAgentLifecycle()
    let observer = FakeLockStateObserver()
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: lifecycle,
      observer: observer,
      initialState: .ready(isLocked: false)
    )
    var activities: [AppCoordinator.Activity?] = []
    coordinator.onSnapshotChange = { activities.append($0.activity) }

    coordinator.performDisplayedLockAction()
    try await waitUntil {
      coordinator.state == .ready(isLocked: true) && coordinator.activity == nil
    }

    #expect(client.lockCallCount == 1)
    #expect(client.unlockCallCount == 0)
    #expect(activities.contains(.locking))
    #expect(observer.initialStates == [true])
  }

  @Test
  @MainActor
  func observedAuthoritativeStateUpdatesReadySnapshotWithoutDuplicatePublication() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let lifecycle = FakeAgentLifecycle()
    let observer = FakeLockStateObserver()
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: lifecycle,
      observer: observer
    )
    var snapshots: [AppCoordinator.Snapshot] = []
    coordinator.onSnapshotChange = { snapshots.append($0) }

    coordinator.reconcile()
    try await waitUntil {
      coordinator.state == .ready(isLocked: false)
    }
    let publicationCountBeforeDuplicate = snapshots.count

    observer.send(false)
    #expect(snapshots.count == publicationCountBeforeDuplicate)

    observer.send(true)
    #expect(coordinator.state == .ready(isLocked: true))
    #expect(snapshots.last?.state == .ready(isLocked: true))
  }

  @Test
  @MainActor
  func safetyCheckWaitsForAuthoritativeUnlockAndCompletes() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver(),
      initialState: .ready(isLocked: false)
    )

    coordinator.startSafetyCheck()
    try await waitUntil {
      coordinator.safetyCheckState == .completed
    }

    #expect(client.beginSafetyCheckCallCount == 1)
    #expect(client.waitUntilUnlockedCallCount == 1)
    #expect(!client.isLocked)
    #expect(coordinator.activity == nil)
  }

  @Test
  @MainActor
  func safetyCheckReportsConcurrentExistingLock() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    client.safetyCheckOutcome = .alreadyLocked
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver(),
      initialState: .ready(isLocked: false)
    )

    coordinator.startSafetyCheck()
    try await waitUntil {
      if case .failed = coordinator.safetyCheckState {
        return true
      }
      return false
    }

    guard case let .failed(message) = coordinator.safetyCheckState else {
      Issue.record("Expected a failed safety check.")
      return
    }
    #expect(message.contains("already locked"))
    #expect(client.waitUntilUnlockedCallCount == 0)
  }

  @MainActor
  private func makeCoordinator(
    client: FakeAgentClient,
    lifecycle: FakeAgentLifecycle,
    observer: FakeLockStateObserver,
    initialState: AppCoordinator.State = .checking(lastKnownLock: nil)
  ) -> AppCoordinator {
    AppCoordinator(
      client: client,
      lifecycle: lifecycle,
      lockStateObserver: observer,
      initialState: initialState
    )
  }

  @MainActor
  private func waitUntil(
    timeout: Duration = .seconds(1),
    _ condition: @escaping @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !condition() {
      guard clock.now < deadline else {
        Issue.record("Timed out waiting for AppCoordinator state")
        throw AppCoordinatorTestError.timedOut
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private enum AppCoordinatorTestError: Error {
  case timedOut
}

@MainActor
private final class FakeAgentClient: AgentClientServing {
  private(set) var beginSafetyCheckCallCount = 0
  private(set) var lockCallCount = 0
  private(set) var unlockCallCount = 0
  private(set) var waitUntilUnlockedCallCount = 0
  var accessibilityPermissionGranted: Bool
  var isLocked: Bool
  var safetyCheckOutcome: LockRequestOutcome = .acquired

  private let descriptor = ServiceDescriptor(
    protocolVersion: ServiceContract.protocolVersion,
    capabilities: ServiceContract.requiredCapabilities,
    agentBundleIdentifier: SharedConstants.agentBundleIdentifier,
    agentVersion: "1.0",
    agentBuild: "1",
    agentInstanceID: UUID()
  )

  init(isLocked: Bool, hasAccessibilityPermission: Bool) {
    self.isLocked = isLocked
    accessibilityPermissionGranted = hasAccessibilityPermission
  }

  func serviceDescriptor() async throws -> ServiceDescriptor {
    descriptor
  }

  func lock() async throws {
    lockCallCount += 1
    isLocked = true
  }

  func beginSafetyCheck() async throws -> LockRequestOutcome {
    beginSafetyCheckCallCount += 1
    if safetyCheckOutcome == .acquired {
      isLocked = true
    }
    return safetyCheckOutcome
  }

  func unlock() async throws {
    unlockCallCount += 1
    isLocked = false
  }

  func status() async throws -> Bool {
    isLocked
  }

  func toggle() async throws -> Bool {
    isLocked.toggle()
    return isLocked
  }

  func prepareForReplacement(
    unlockIfNeeded: Bool,
    expectedAgentInstanceID: UUID
  ) async throws -> ServiceReplacementTicket {
    if unlockIfNeeded {
      isLocked = false
    }
    return ServiceReplacementTicket(
      id: UUID(),
      agentInstanceID: expectedAgentInstanceID
    )
  }

  func cancelReplacementPreparation(ticket _: ServiceReplacementTicket) async throws {}

  func commitReplacement(ticket _: ServiceReplacementTicket) async throws {}

  func hasAccessibilityPermission() async throws -> Bool {
    accessibilityPermissionGranted
  }

  func requestAccessibilityPermission() async throws {}

  func waitUntilUnlocked() async throws {
    waitUntilUnlockedCallCount += 1
    isLocked = false
  }

  func resetConnection() {}
}

@MainActor
private final class FakeAgentLifecycle: AgentLifecycleServing {
  func ensureEnabled() -> AgentRegistrar.State {
    .enabled
  }

  func compatibility(
    of _: ServiceDescriptor
  ) -> AgentRegistrar.Compatibility {
    .compatible
  }

  func restart() async -> AgentRegistrar.State {
    .enabled
  }
}

@MainActor
private final class FakeLockStateObserver: AgentLockStateObserving {
  private(set) var initialStates: [Bool?] = []
  private var handler: ((Bool) -> Void)?

  func subscribe(
    initialState: Bool?,
    _ handler: @escaping (Bool) -> Void
  ) -> ObserverToken {
    initialStates.append(initialState)
    self.handler = handler
    return ObserverToken {}
  }

  func send(_ isLocked: Bool) {
    handler?(isLocked)
  }
}
