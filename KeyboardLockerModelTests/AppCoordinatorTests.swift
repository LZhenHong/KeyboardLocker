import Client
import Foundation
import XCTest

final class AppCoordinatorTests: XCTestCase {
  @MainActor
  func testReconcilePublishesAuthoritativeReadySnapshot() async throws {
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

    XCTAssertEqual(coordinator.snapshot, AppCoordinator.Snapshot(
      state: .ready(isLocked: false),
      activity: nil,
      lastError: nil
    ))
    XCTAssertEqual(observer.initialStates, [false])
    XCTAssertEqual(snapshots.last, coordinator.snapshot)
  }

  @MainActor
  func testDisplayedLockActionLocksThroughClientThenReconcilesAuthoritativeState() async throws {
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

    XCTAssertEqual(client.lockCallCount, 1)
    XCTAssertEqual(client.unlockCallCount, 0)
    XCTAssertTrue(activities.contains(.locking))
    XCTAssertEqual(observer.initialStates, [true])
  }

  @MainActor
  func testObservedAuthoritativeStateUpdatesReadySnapshotWithoutDuplicatePublication() async throws {
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
    XCTAssertEqual(snapshots.count, publicationCountBeforeDuplicate)

    observer.send(true)
    XCTAssertEqual(coordinator.state, .ready(isLocked: true))
    XCTAssertEqual(snapshots.last?.state, .ready(isLocked: true))
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
        XCTFail("Timed out waiting for AppCoordinator state")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

@MainActor
private final class FakeAgentClient: AgentClientServing {
  private(set) var lockCallCount = 0
  private(set) var unlockCallCount = 0
  var accessibilityPermissionGranted: Bool
  var isLocked: Bool

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
