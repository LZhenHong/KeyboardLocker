import Client
import CoreGraphics
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct AppUIStoreTests {
  // MARK: - Settings presentation

  @Test
  func editableSettingsAreAbsentWhileTheyAreStillLoading() {
    let store = makeStore(snapshot: makeSnapshot(settingsState: .loading))

    #expect(store.editableSettings == nil)
    #expect(store.settingsUnavailableMessage == nil)
    #expect(!store.canEditSettings)
  }

  /// A read failure must never be presented as a usable configuration: showing `.default` would
  /// display an unlock hotkey the Agent is not actually using.
  @Test
  func unavailableSettingsExposeTheMessageAndNoValues() {
    let store = makeStore(
      snapshot: makeSnapshot(settingsState: .unavailable("agent unreachable"))
    )

    #expect(store.editableSettings == nil)
    #expect(store.settingsUnavailableMessage == "agent unreachable")
    #expect(!store.canEditSettings)
  }

  @Test
  func loadedSettingsBecomeEditableWhenIdle() {
    let store = makeStore(snapshot: makeSnapshot(settingsState: .loaded(.default)))

    #expect(store.editableSettings == .default)
    #expect(store.canEditSettings)
  }

  @Test
  func settingsAreNotEditableWhileAnActionIsInFlight() {
    let store = makeStore(
      snapshot: makeSnapshot(
        activity: .applyingSettings,
        settingsState: .loaded(.default)
      )
    )

    #expect(store.isBusy)
    #expect(!store.canEditSettings)
  }

  /// While locked, the stored values and the values the lock enforces are different things; the
  /// store must expose both so the UI can say a change is pending.
  @Test
  func storedAndActiveSettingsAreReportedSeparatelyWhileLocked() {
    let stored = makeSettings(autoUnlockSeconds: 30)
    let store = makeStore(
      snapshot: makeSnapshot(
        state: .ready(isLocked: true),
        lockSnapshot: makeLockSnapshot(isLocked: true, settings: .default),
        settingsState: .loaded(stored)
      )
    )

    #expect(store.editableSettings == stored)
    #expect(store.activeSettings == .default)
    #expect(store.snapshot.hasSettingsPendingNextLock)
  }

  @Test
  func noPendingChangeIsReportedWhenTheLockAlreadyEnforcesStoredSettings() {
    let store = makeStore(
      snapshot: makeSnapshot(
        state: .ready(isLocked: true),
        lockSnapshot: makeLockSnapshot(isLocked: true, settings: .default),
        settingsState: .loaded(.default)
      )
    )

    #expect(!store.snapshot.hasSettingsPendingNextLock)
  }

  @Test
  func noPendingChangeIsReportedWhileUnlocked() {
    let store = makeStore(
      snapshot: makeSnapshot(
        state: .ready(isLocked: false),
        lockSnapshot: makeLockSnapshot(isLocked: false, settings: .default),
        settingsState: .loaded(makeSettings(autoUnlockSeconds: 30))
      )
    )

    #expect(!store.snapshot.hasSettingsPendingNextLock)
  }

  // MARK: - Lock detail

  @Test
  func lockDetailIsDerivedFromTheAuthoritativeSnapshot() {
    let started = Date(timeIntervalSinceReferenceDate: 100)
    let deadline = Date(timeIntervalSinceReferenceDate: 160)
    let store = makeStore(
      snapshot: makeSnapshot(
        state: .ready(isLocked: true),
        lockSnapshot: LockStatusSnapshot(
          capturedAt: started,
          isLocked: true,
          startedAt: started,
          autoUnlockTargetDate: deadline,
          settings: .default
        ),
        settingsState: .loaded(.default)
      )
    )

    #expect(store.isLocked)
    #expect(store.lockStartDate == started)
    #expect(store.autoUnlockDeadline == deadline)
  }

  @Test
  func lockDetailIsAbsentWhenTheAgentCouldNotProvideIt() {
    let store = makeStore(
      snapshot: makeSnapshot(
        state: .unavailable(message: "unreachable", canRestartAgent: true),
        settingsState: .unavailable("unreachable")
      )
    )

    #expect(store.autoUnlockDeadline == nil)
    #expect(store.lockStartDate == nil)
    #expect(store.activeSettings == nil)
  }

  // MARK: - Lock action availability

  @Test
  func lockActionIsOfferedWhenReady() {
    let store = makeStore(snapshot: makeSnapshot(state: .ready(isLocked: false)))

    #expect(store.canPerformLockAction)
  }

  /// Unlock has to stay reachable in degraded states, otherwise a locked keyboard loses its
  /// in-window escape hatch.
  @Test(arguments: [
    AppCoordinator.State.accessibilityRequired(isLocked: true),
    .checking(lastKnownLock: true),
    .agentUpdateRequired(isLocked: true, message: "update"),
  ])
  func unlockRemainsOfferedInDegradedLockedStates(state: AppCoordinator.State) {
    let store = makeStore(snapshot: makeSnapshot(state: state))

    #expect(store.canPerformLockAction)
  }

  @Test(arguments: [
    AppCoordinator.State.accessibilityRequired(isLocked: false),
    .agentApprovalRequired,
    .agentReplacementInProgress(message: "replacing"),
    .checking(lastKnownLock: nil),
    .unavailable(message: "unreachable", canRestartAgent: true),
  ])
  func lockActionIsWithheldWhenTheAgentCannotHonorIt(state: AppCoordinator.State) {
    let store = makeStore(snapshot: makeSnapshot(state: state))

    #expect(!store.canPerformLockAction)
  }

  @Test
  func lockActionIsWithheldWhileAnActionIsInFlight() {
    let store = makeStore(
      snapshot: makeSnapshot(state: .ready(isLocked: false), activity: .locking)
    )

    #expect(!store.canPerformLockAction)
  }

  // MARK: - Fixtures

  private func makeStore(snapshot: AppCoordinator.Snapshot) -> AppUIStore {
    let store = AppUIStore(
      coordinator: AppCoordinator(
        client: UnusedAgentClient(),
        lifecycle: UnusedAgentLifecycle(),
        lockStateObserver: UnusedLockStateObserver(),
        initialState: snapshot.state
      )
    )
    store.receive(snapshot)
    return store
  }

  private func makeSnapshot(
    state: AppCoordinator.State = .ready(isLocked: false),
    activity: AppCoordinator.Activity? = nil,
    lockSnapshot: LockStatusSnapshot? = nil,
    settingsState: AppCoordinator.SettingsState = .loading
  ) -> AppCoordinator.Snapshot {
    AppCoordinator.Snapshot(
      state: state,
      activity: activity,
      lastError: nil,
      safetyCheckState: .idle,
      lockSnapshot: lockSnapshot,
      settingsState: settingsState
    )
  }

  private func makeLockSnapshot(
    isLocked: Bool,
    settings: KeyboardLockerSettings
  ) -> LockStatusSnapshot {
    LockStatusSnapshot(
      capturedAt: Date(timeIntervalSinceReferenceDate: 0),
      isLocked: isLocked,
      startedAt: isLocked ? Date(timeIntervalSinceReferenceDate: 0) : nil,
      autoUnlockTargetDate: nil,
      settings: settings
    )
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
}

/// The store's derived state is a pure function of the snapshot it is handed, so these doubles only
/// exist to satisfy the coordinator's initializer and must never be called.
@MainActor
private struct UnusedAgentClient: AgentClientServing {
  func serviceDescriptor() async throws -> ServiceDescriptor {
    unexpected()
  }

  func lock() async throws {
    unexpected()
  }

  func unlock() async throws {
    unexpected()
  }

  func status() async throws -> Bool {
    unexpected()
  }

  func toggle() async throws -> Bool {
    unexpected()
  }

  func beginSafetyCheck() async throws -> LockRequestOutcome {
    unexpected()
  }

  func waitUntilUnlocked() async throws {
    unexpected()
  }

  func hasAccessibilityPermission() async throws -> Bool {
    unexpected()
  }

  func requestAccessibilityPermission() async throws {
    unexpected()
  }

  func currentSettings() async throws -> KeyboardLockerSettings {
    unexpected()
  }

  func applySettings(
    _: KeyboardLockerSettings
  ) async throws -> KeyboardLockerSettings {
    unexpected()
  }

  func lockStatusSnapshot() async throws -> LockStatusSnapshot {
    unexpected()
  }

  func prepareForReplacement(
    unlockIfNeeded _: Bool,
    expectedAgentInstanceID _: UUID
  ) async throws -> ServiceReplacementTicket {
    unexpected()
  }

  func cancelReplacementPreparation(ticket _: ServiceReplacementTicket) async throws {
    unexpected()
  }

  func commitReplacement(ticket _: ServiceReplacementTicket) async throws {
    unexpected()
  }

  func resetConnection() {}

  private func unexpected() -> Never {
    fatalError("AppUIStore must not reach the Agent to derive presentation state.")
  }
}

@MainActor
private struct UnusedAgentLifecycle: AgentLifecycleServing {
  func ensureEnabled() -> AgentRegistrar.State {
    .enabled
  }

  func compatibility(of _: ServiceDescriptor) -> AgentRegistrar.Compatibility {
    .compatible
  }

  func restart() async -> AgentRegistrar.State {
    .enabled
  }
}

@MainActor
private struct UnusedLockStateObserver: AgentLockStateObserving {
  func subscribe(
    initialState _: Bool?,
    _: @escaping (Bool) -> Void
  ) -> ObserverToken {
    ObserverToken {}
  }
}
