import Client
import CoreGraphics
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
    // Readiness and the Agent detail it unlocks arrive in separate turns; wait for both so the
    // published snapshot is the settled one.
    try await waitUntil {
      coordinator.state == .ready(isLocked: false)
        && coordinator.settingsState == .loaded(.default)
    }

    #expect(coordinator.snapshot == AppCoordinator.Snapshot(
      state: .ready(isLocked: false),
      activity: nil,
      lastError: nil,
      safetyCheckState: .idle,
      lockSnapshot: LockStatusSnapshot(
        capturedAt: Date(timeIntervalSinceReferenceDate: 0),
        isLocked: false,
        startedAt: nil,
        autoUnlockTargetDate: nil,
        settings: .default
      ),
      settingsState: .loaded(.default)
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
  func timedLockLocksThroughClientWithTheOneOffOverrideThenReconciles() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver(),
      initialState: .ready(isLocked: false)
    )
    var activities: [AppCoordinator.Activity?] = []
    coordinator.onSnapshotChange = { activities.append($0.activity) }

    coordinator.performTimedLock(seconds: 600)
    try await waitUntil {
      coordinator.state == .ready(isLocked: true) && coordinator.activity == nil
    }

    #expect(client.beginTimedLockCalls == [600])
    #expect(client.lockCallCount == 0)
    #expect(activities.contains(.locking))
  }

  @Test
  @MainActor
  func timedLockIsNotOfferedWhileLocked() async throws {
    let client = FakeAgentClient(isLocked: true, hasAccessibilityPermission: true)
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver(),
      initialState: .ready(isLocked: true)
    )

    // A running lock never adopts an override, so the guard swallows the action synchronously.
    coordinator.performTimedLock(seconds: 600)

    #expect(client.beginTimedLockCalls.isEmpty)
    #expect(coordinator.activity == nil)
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

  // MARK: - Settings

  @Test
  @MainActor
  func applySettingsAdoptsTheValuesTheAgentReportsStored() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver()
    )
    coordinator.reconcile()
    try await waitUntil { coordinator.state == .ready(isLocked: false) }

    // A fractional timeout the Agent normalizes to whole seconds: adopting the request instead of
    // the reply would leave the UI showing a value that was never stored.
    coordinator.applySettings(makeSettings(autoUnlockSeconds: 59.6))
    try await waitUntil {
      coordinator.settingsState == .loaded(makeSettings(autoUnlockSeconds: 60))
    }

    #expect(client.appliedSettings.count == 1)
    #expect(coordinator.snapshot.lastError == nil)
    #expect(coordinator.snapshot.activity == nil)
  }

  @Test
  @MainActor
  func applySettingsWhileLockedReportsThemAsPendingTheNextLock() async throws {
    let client = FakeAgentClient(isLocked: true, hasAccessibilityPermission: true)
    // The running lock keeps enforcing the settings it started with.
    client.activeSettings = .default
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver()
    )
    coordinator.reconcile()
    try await waitUntil { coordinator.state == .ready(isLocked: true) }

    let desired = makeSettings(autoUnlockSeconds: 30)
    coordinator.applySettings(desired)
    try await waitUntil {
      coordinator.settingsState == .loaded(desired)
        && coordinator.lockSnapshot != nil
    }

    #expect(coordinator.snapshot.hasSettingsPendingNextLock)
    #expect(coordinator.lockSnapshot?.settings == .default)
    #expect(coordinator.snapshot.lastError == nil)
  }

  @Test
  @MainActor
  func settingsPendingIsNotReportedWhenTheLockAlreadyEnforcesThem() async throws {
    let client = FakeAgentClient(isLocked: true, hasAccessibilityPermission: true)
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver()
    )
    coordinator.reconcile()
    try await waitUntil {
      coordinator.state == .ready(isLocked: true)
        && coordinator.settingsState == .loaded(.default)
    }

    #expect(!coordinator.snapshot.hasSettingsPendingNextLock)
  }

  @Test
  @MainActor
  func failedSettingsWriteSurfacesTheErrorAndKeepsStoredValues() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver()
    )
    coordinator.reconcile()
    try await waitUntil { coordinator.settingsState == .loaded(.default) }
    client.applySettingsError = AppCoordinatorTestError.expected

    coordinator.applySettings(makeSettings(autoUnlockSeconds: 30))
    try await waitUntil { coordinator.snapshot.lastError != nil }

    #expect(coordinator.settingsState == .loaded(.default))
    #expect(coordinator.snapshot.activity == nil)
  }

  /// Presenting `.default` on a read failure would invent a second source of truth and could show
  /// an unlock hotkey the Agent is not using.
  @Test
  @MainActor
  func unreadableSettingsBecomeExplicitlyUnavailable() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    client.currentSettingsError = AppCoordinatorTestError.expected
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver()
    )

    coordinator.reconcile()
    try await waitUntil {
      if case .unavailable = coordinator.settingsState {
        return true
      }
      return false
    }

    #expect(coordinator.settingsState.settings == nil)
    // A detail failure must not downgrade an otherwise ready agent.
    #expect(coordinator.state == .ready(isLocked: false))
  }

  @Test
  @MainActor
  func anUnreachableAgentClearsSettingsInsteadOfKeepingStaleOnes() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let lifecycle = FakeAgentLifecycle()
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: lifecycle,
      observer: FakeLockStateObserver()
    )
    coordinator.reconcile()
    try await waitUntil { coordinator.settingsState == .loaded(.default) }

    lifecycle.registrationState = .approvalRequired
    coordinator.reconcile()
    try await waitUntil { coordinator.state == .agentApprovalRequired }

    #expect(coordinator.settingsState.settings == nil)
    #expect(coordinator.lockSnapshot == nil)
  }

  private func makeSettings(
    autoUnlockSeconds: TimeInterval
  ) -> KeyboardLockerSettings {
    KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: autoUnlockSeconds),
      unlockHotkey: KeyboardLockerSettings.Hotkey(
        keyCode: CGKeyCode(SharedConstants.defaultUnlockKeyCode),
        modifierFlags: [.maskControl, .maskAlternate]
      )
    )
  }

  @Test
  @MainActor
  func performLockLocksThroughClientAndSettlesBackToReady() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver(),
      initialState: .ready(isLocked: false)
    )

    coordinator.performLock()
    try await waitUntil {
      coordinator.activity == nil && coordinator.state == .ready(isLocked: true)
    }

    #expect(client.lockCallCount == 1)
    #expect(coordinator.lastError == nil)
  }

  @Test
  @MainActor
  func performLockSurfacesFailureWithoutTouchingState() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    client.lockError = AppCoordinatorTestError.expected
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver(),
      initialState: .ready(isLocked: false)
    )

    coordinator.performLock()
    try await waitUntil {
      coordinator.activity == nil && coordinator.lastError != nil
    }

    #expect(client.lockCallCount == 1)
    #expect(coordinator.state == .ready(isLocked: false))
  }

  @Test
  @MainActor
  func loadLockHistoryPublishesLoadedEntries() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    let entries = [
      LockHistoryEntry(
        startedAt: Date(timeIntervalSinceReferenceDate: 10_000),
        endedAt: Date(timeIntervalSinceReferenceDate: 10_090),
        reason: .explicit
      ),
    ]
    client.lockHistoryResult = .success(LockHistory(entries: entries))
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver(),
      initialState: .ready(isLocked: false)
    )

    coordinator.loadLockHistory()
    try await waitUntil {
      coordinator.historyState == .loaded(entries)
    }

    #expect(client.lockHistoryCallCount == 1)
  }

  @Test
  @MainActor
  func failedHistoryLoadBecomesUnavailableWithoutDowngradingReadyState() async throws {
    let client = FakeAgentClient(isLocked: false, hasAccessibilityPermission: true)
    client.lockHistoryResult = .failure(AppCoordinatorTestError.expected)
    let coordinator = makeCoordinator(
      client: client,
      lifecycle: FakeAgentLifecycle(),
      observer: FakeLockStateObserver(),
      initialState: .ready(isLocked: false)
    )

    coordinator.loadLockHistory()
    try await waitUntil {
      if case .unavailable = coordinator.historyState {
        return true
      }
      return false
    }

    // History is presentation detail: its failure must not downgrade a ready state.
    #expect(coordinator.state == .ready(isLocked: false))
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
  case expected
  case timedOut
}

@MainActor
private final class FakeAgentClient: AgentClientServing {
  private(set) var beginSafetyCheckCallCount = 0
  private(set) var beginTimedLockCalls: [TimeInterval] = []
  private(set) var lockCallCount = 0
  private(set) var unlockCallCount = 0
  private(set) var waitUntilUnlockedCallCount = 0
  private(set) var appliedSettings: [KeyboardLockerSettings] = []
  var accessibilityPermissionGranted: Bool
  var isLocked: Bool
  var safetyCheckOutcome: LockRequestOutcome = .acquired
  var timedLockOutcome: LockRequestOutcome = .acquired
  var storedSettings: KeyboardLockerSettings = .default
  var currentSettingsError: Error?
  var applySettingsError: Error?
  var lockStatusSnapshotError: Error?
  var lockError: Error?
  var lockHistoryResult: Result<LockHistory, Error> = .success(LockHistory(entries: []))
  private(set) var lockHistoryCallCount = 0
  /// What a running lock is enforcing. Distinct from `storedSettings` so tests can model a write
  /// that landed while locked and only takes effect on the next lock.
  var activeSettings: KeyboardLockerSettings?

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
    if let lockError {
      throw lockError
    }
    isLocked = true
  }

  func beginSafetyCheck() async throws -> LockRequestOutcome {
    beginSafetyCheckCallCount += 1
    if safetyCheckOutcome == .acquired {
      isLocked = true
    }
    return safetyCheckOutcome
  }

  func beginTimedLock(seconds: TimeInterval) async throws -> LockRequestOutcome {
    beginTimedLockCalls.append(seconds)
    if timedLockOutcome == .acquired {
      isLocked = true
    }
    return timedLockOutcome
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

  func currentSettings() async throws -> KeyboardLockerSettings {
    if let currentSettingsError {
      throw currentSettingsError
    }
    return storedSettings
  }

  func applySettings(
    _ settings: KeyboardLockerSettings
  ) async throws -> KeyboardLockerSettings {
    if let applySettingsError {
      throw applySettingsError
    }
    appliedSettings.append(settings)
    // Mirrors the Agent: values are normalized before being stored, and a running lock keeps
    // enforcing whatever it started with.
    storedSettings = try settings.validated()
    return storedSettings
  }

  func lockStatusSnapshot() async throws -> LockStatusSnapshot {
    if let lockStatusSnapshotError {
      throw lockStatusSnapshotError
    }
    return LockStatusSnapshot(
      capturedAt: Date(timeIntervalSinceReferenceDate: 0),
      isLocked: isLocked,
      startedAt: isLocked ? Date(timeIntervalSinceReferenceDate: 0) : nil,
      autoUnlockTargetDate: nil,
      settings: activeSettings ?? storedSettings
    )
  }

  func lockHistory() async throws -> LockHistory {
    lockHistoryCallCount += 1
    return try lockHistoryResult.get()
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
  var registrationState: AgentRegistrar.State = .enabled

  func ensureEnabled() -> AgentRegistrar.State {
    registrationState
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
