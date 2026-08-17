import Client
import Foundation

/// Coordinates App-side lock actions, readiness, and Agent replacement without owning domain state.
@MainActor
final class AppCoordinator {
  enum State: Equatable {
    case checking(lastKnownLock: Bool?)
    case agentApprovalRequired
    case agentReplacementInProgress(message: String)
    case agentUpdateRequired(isLocked: Bool?, message: String)
    case accessibilityRequired(isLocked: Bool)
    case ready(isLocked: Bool)
    case unavailable(message: String, canRestartAgent: Bool)

    var knownLockState: Bool? {
      switch self {
      case let .checking(lastKnownLock):
        lastKnownLock
      case let .agentUpdateRequired(isLocked, _):
        isLocked
      case let .accessibilityRequired(isLocked),
           let .ready(isLocked):
        isLocked
      case .agentApprovalRequired, .agentReplacementInProgress, .unavailable:
        nil
      }
    }
  }

  enum Activity: Equatable {
    case applyingSettings
    case locking
    case requestingAccessibility
    case restartingAgent
    case startingSafetyCheck
    case unlocking
    case updatingAgent
  }

  enum SafetyCheckState: Equatable {
    case completed
    case failed(String)
    case idle
    case running
  }

  /// The Agent's persisted configuration — what the next lock will use, and what the settings UI
  /// edits. A read failure stays `unavailable`: presenting `.default` would invent a second
  /// source of truth and could show an unlock hotkey the Agent is not actually using.
  enum SettingsState: Equatable {
    case loading
    case loaded(KeyboardLockerSettings)
    case unavailable(String)

    var settings: KeyboardLockerSettings? {
      guard case let .loaded(settings) = self else {
        return nil
      }
      return settings
    }
  }

  struct Snapshot: Equatable {
    let state: State
    let activity: Activity?
    let lastError: String?
    let safetyCheckState: SafetyCheckState
    /// Authoritative point-in-time lock detail: start time, deadline, and the settings a running
    /// lock is enforcing. `nil` when the Agent could not be reached for it.
    let lockSnapshot: LockStatusSnapshot?
    let settingsState: SettingsState

    /// Agent-supplied detail defaults to absent so callers that only care about readiness — tests
    /// and previews — do not have to describe a lock snapshot they are not exercising.
    init(
      state: State,
      activity: Activity?,
      lastError: String?,
      safetyCheckState: SafetyCheckState,
      lockSnapshot: LockStatusSnapshot? = nil,
      settingsState: SettingsState = .loading
    ) {
      self.state = state
      self.activity = activity
      self.lastError = lastError
      self.safetyCheckState = safetyCheckState
      self.lockSnapshot = lockSnapshot
      self.settingsState = settingsState
    }

    /// Whether stored settings differ from what the running lock enforces, i.e. a write landed
    /// while locked and takes effect on the next lock.
    var hasSettingsPendingNextLock: Bool {
      guard let lockSnapshot, lockSnapshot.isLocked,
            let stored = settingsState.settings
      else {
        return false
      }
      return stored != lockSnapshot.settings
    }
  }

  private(set) var state: State = .checking(lastKnownLock: nil) {
    didSet {
      publishSnapshotIfNeeded()
    }
  }

  private(set) var activity: Activity? {
    didSet {
      publishSnapshotIfNeeded()
    }
  }

  private(set) var lastError: String? {
    didSet {
      publishSnapshotIfNeeded()
    }
  }

  private(set) var safetyCheckState: SafetyCheckState = .idle {
    didSet {
      publishSnapshotIfNeeded()
    }
  }

  private(set) var lockSnapshot: LockStatusSnapshot? {
    didSet {
      publishSnapshotIfNeeded()
    }
  }

  private(set) var settingsState: SettingsState = .loading {
    didSet {
      publishSnapshotIfNeeded()
    }
  }

  var snapshot: Snapshot {
    Snapshot(
      state: state,
      activity: activity,
      lastError: lastError,
      safetyCheckState: safetyCheckState,
      lockSnapshot: lockSnapshot,
      settingsState: settingsState
    )
  }

  var onSnapshotChange: ((Snapshot) -> Void)? {
    didSet {
      publishSnapshotIfNeeded(force: true)
    }
  }

  private var agentDetailTask: Task<Void, Never>?
  private var reconciliationTask: Task<Void, Never>?
  private var needsFollowUpReconciliation = false
  private var pendingUpdatePlan: AgentUpdatePlan?
  private var attemptedAutomaticUpdateBuilds: Set<String> = []
  private var stateToken: ObserverToken?
  private let client: any AgentClientServing
  private let lifecycle: any AgentLifecycleServing
  private let lockStateObserver: any AgentLockStateObserving
  private let readinessCoordinator: AgentReadinessCoordinator
  private let replacementCoordinator: AgentReplacementCoordinator
  private var lastPublishedSnapshot: Snapshot?

  private static let replacementProgressPollInterval: Duration = .seconds(3)

  convenience init() {
    self.init(
      client: LiveAgentClient(),
      lifecycle: LiveAgentLifecycle(),
      lockStateObserver: LiveAgentLockStateObserver(),
      initialState: .checking(lastKnownLock: nil)
    )
    reconcile()
  }

  init(
    client: any AgentClientServing,
    lifecycle: any AgentLifecycleServing,
    lockStateObserver: any AgentLockStateObserving,
    initialState: State
  ) {
    self.client = client
    self.lifecycle = lifecycle
    self.lockStateObserver = lockStateObserver
    readinessCoordinator = AgentReadinessCoordinator(
      client: client,
      lifecycle: lifecycle
    )
    replacementCoordinator = AgentReplacementCoordinator(
      client: client,
      lifecycle: lifecycle
    )
    state = initialState
  }

  /// Rebuilds the complete readiness snapshot from Service Management and the Agent.
  func reconcile() {
    guard activity == nil else {
      return
    }
    startReconciliation()
  }

  /// Performs the direction the menu currently displays, as an explicit idempotent lock/unlock.
  /// Deliberately not the atomic `toggle()`: the escape-hatch states below must only ever
  /// unlock, and explicit verbs still work on legacy agents without the `lockToggle` capability.
  func performDisplayedLockAction() {
    guard activity == nil else {
      return
    }

    let isLocked: Bool
    let allowsAutomaticAgentUpdateAfterAction: Bool
    switch state {
    case let .ready(currentLockState):
      isLocked = currentLockState
      allowsAutomaticAgentUpdateAfterAction = true

    case .checking(lastKnownLock: true):
      isLocked = true
      allowsAutomaticAgentUpdateAfterAction = true

    case .accessibilityRequired(isLocked: true):
      // Unlock must remain available if permission is revoked while the Agent still reports locked.
      isLocked = true
      allowsAutomaticAgentUpdateAfterAction = true

    case .agentUpdateRequired(isLocked: true, message: _):
      // Unlock must remain independently available without forcing an Agent replacement.
      isLocked = true
      allowsAutomaticAgentUpdateAfterAction = false

    default:
      return
    }

    reconciliationTask?.cancel()
    activity = isLocked ? .unlocking : .locking
    lastError = nil

    Task { [weak self] in
      guard let self else {
        return
      }

      var actionError: String?
      do {
        if isLocked {
          try await client.unlock()
        } else {
          try await client.lock()
        }
      } catch {
        actionError = error.localizedDescription
      }

      activity = nil
      startReconciliation(
        preserving: actionError,
        allowsAutomaticAgentUpdate: allowsAutomaticAgentUpdateAfterAction
      )
    }
  }

  /// Starts the Agent-owned ten-second recovery check, then waits for authoritative unlock.
  /// The App never owns the timer; quitting after acquisition still leaves the Agent fail-safe.
  func startSafetyCheck() {
    guard case .ready(isLocked: false) = state,
          activity == nil,
          safetyCheckState != .running
    else {
      return
    }

    reconciliationTask?.cancel()
    activity = .startingSafetyCheck
    safetyCheckState = .running
    lastError = nil

    Task { [weak self] in
      guard let self else {
        return
      }

      do {
        let outcome = try await client.beginSafetyCheck()
        guard outcome == .acquired else {
          throw SafetyCheckError.lockAlreadyActive
        }

        // Acquisition is complete, so ordinary global unlock actions must remain available while
        // this task only waits for the Agent's authoritative state to return to unlocked.
        activity = nil
        startReconciliation()
        try await client.waitUntilUnlocked()
        safetyCheckState = .completed
        startReconciliation()
      } catch {
        let message = error.localizedDescription
        activity = nil
        safetyCheckState = .failed(message)
        startReconciliation(preserving: message)
      }
    }
  }

  /// Stores a new configuration in the Agent and adopts the values it reports back.
  ///
  /// Callers must pass values that already satisfy `KeyboardLockerSettings.validated()`; the Agent
  /// enforces the same rules and rejects anything else. A running lock is unaffected — the stored
  /// values take effect on the next lock.
  func applySettings(_ settings: KeyboardLockerSettings) {
    guard activity == nil else {
      return
    }

    reconciliationTask?.cancel()
    activity = .applyingSettings
    lastError = nil

    Task { [weak self] in
      guard let self else {
        return
      }

      var actionError: String?
      do {
        // The reply is authoritative: validation normalizes values, so the request is not
        // necessarily what ended up stored.
        settingsState = .loaded(try await client.applySettings(settings))
      } catch {
        actionError = error.localizedDescription
      }

      activity = nil
      // Re-reads the authoritative lock snapshot so a locked keyboard's unchanged active settings
      // become visible next to the newly stored ones.
      startReconciliation(preserving: actionError)
    }
  }

  func requestAccessibilityPermission() {
    guard case .accessibilityRequired = state, activity == nil else {
      return
    }

    reconciliationTask?.cancel()
    activity = .requestingAccessibility
    lastError = nil

    Task { [weak self] in
      guard let self else {
        return
      }

      var actionError: String?
      do {
        try await client.requestAccessibilityPermission()
      } catch {
        actionError = error.localizedDescription
      }

      activity = nil
      // The system prompt is asynchronous; only a fresh Agent query can confirm permission.
      startReconciliation(preserving: actionError)
    }
  }

  func restartAgent() {
    guard case .unavailable(message: _, canRestartAgent: true) = state,
          activity == nil
    else {
      return
    }

    activity = .restartingAgent
    lastError = nil
    stopStateObservation()

    Task { [weak self] in
      guard let self else {
        return
      }
      defer {
        activity = nil
      }

      // Gracefully clear the logical lock when possible; unregistering the Agent still releases
      // its event tap if the old process is incompatible or unresponsive.
      try? await client.unlock()
      client.resetConnection()
      let registrationState = await lifecycle.restart()
      client.resetConnection()

      guard case .enabled = registrationState else {
        _ = applyRegistrationState(registrationState)
        return
      }
      await refresh(
        preserving: nil,
        allowsAutomaticAgentUpdate: false
      )
    }
  }

  func updateAgent() {
    guard case .agentUpdateRequired = state,
          let updatePlan = pendingUpdatePlan,
          activity == nil
    else {
      return
    }

    reconciliationTask?.cancel()
    activity = .updatingAgent
    lastError = nil
    stopStateObservation()

    Task { [weak self] in
      guard let self else {
        return
      }

      defer {
        activity = nil
      }

      let outcome = await replacementCoordinator.replace(updatePlan)
      await handleAgentReplacementOutcome(
        outcome,
        updatePlan: updatePlan,
        preserving: nil
      )
    }
  }

  private func startReconciliation(
    preserving actionError: String? = nil,
    allowsAutomaticAgentUpdate: Bool = true
  ) {
    reconciliationTask?.cancel()
    stopStateObservation()

    let lastKnownLock = state.knownLockState

    needsFollowUpReconciliation = false
    state = .checking(lastKnownLock: lastKnownLock)
    lastError = nil

    reconciliationTask = Task { [weak self] in
      await self?.refresh(
        preserving: actionError,
        allowsAutomaticAgentUpdate: allowsAutomaticAgentUpdate,
        expectedPreviousAgentInstanceID: nil
      )
    }
  }

  private func refresh(
    preserving actionError: String?,
    allowsAutomaticAgentUpdate: Bool,
    expectedPreviousAgentInstanceID: UUID? = nil
  ) async {
    let outcome = await readinessCoordinator.inspect(
      expectedPreviousAgentInstanceID: expectedPreviousAgentInstanceID
    )
    guard !Task.isCancelled else {
      return
    }

    switch outcome {
    case .agentDidNotRestart:
      await showServiceFailure(AgentUpdateError.agentDidNotRestart)

    case .cancelled:
      return

    case let .failure(error, context):
      await showServiceFailure(error, context: context)

    case let .invalidBundle(failure):
      pendingUpdatePlan = nil
      clearAgentDetail(reason: failure.message)
      state = .unavailable(message: failure.message, canRestartAgent: false)
      lastError = nil

    case let .ready(isLocked, hasAccessibilityPermission):
      pendingUpdatePlan = nil
      state = hasAccessibilityPermission
        ? .ready(isLocked: isLocked)
        : .accessibilityRequired(isLocked: isLocked)
      lastError = actionError
      startStateObservation()
      startAgentDetailRefresh()

      if needsFollowUpReconciliation {
        startReconciliation(
          preserving: actionError,
          allowsAutomaticAgentUpdate: allowsAutomaticAgentUpdate
        )
      }

    case let .registration(registrationState):
      _ = applyRegistrationState(registrationState)

    case let .replacementInProgress(descriptor):
      showAgentReplacementInProgress(descriptor: descriptor)

    case let .updateAvailable(descriptor, message, bundledBuild, isLocked):
      if !isLocked,
         allowsAutomaticAgentUpdate,
         !attemptedAutomaticUpdateBuilds.contains(bundledBuild) {
        attemptedAutomaticUpdateBuilds.insert(bundledBuild)
        await replaceAgentAutomatically(
          descriptor,
          updateMessage: message,
          preserving: actionError
        )
      } else {
        showAgentUpdateRequired(plan: AgentUpdatePlan(
          mode: .safe(descriptor: descriptor, isLocked: isLocked),
          message: message
        ))
      }

    case let .updateRequired(updatePlan):
      showAgentUpdateRequired(plan: updatePlan)
    }
  }

  private func replaceAgentAutomatically(
    _ previousDescriptor: ServiceDescriptor,
    updateMessage: String,
    preserving actionError: String?
  ) async {
    guard !Task.isCancelled else {
      return
    }

    activity = .updatingAgent
    defer {
      activity = nil
    }

    let updatePlan = AgentUpdatePlan(
      mode: .safe(descriptor: previousDescriptor, isLocked: false),
      message: updateMessage
    )
    let outcome = await replacementCoordinator.replace(updatePlan)
    await handleAgentReplacementOutcome(
      outcome,
      updatePlan: updatePlan,
      preserving: actionError
    )
  }

  private func handleAgentReplacementOutcome(
    _ outcome: AgentReplacementCoordinator.Outcome,
    updatePlan: AgentUpdatePlan,
    preserving actionError: String?
  ) async {
    switch outcome {
    case let .failed(error, currentLockState):
      if let currentLockState {
        showAgentUpdateRequired(
          plan: updatePlan.updatingLockState(currentLockState)
        )
        lastError = error.localizedDescription
      } else {
        await showServiceFailure(error)
      }

    case let .registration(registrationState):
      _ = applyRegistrationState(registrationState)

    case let .replacementInProgress(descriptor):
      showAgentReplacementInProgress(descriptor: descriptor)

    case let .restarted(previousAgentInstanceID):
      await refresh(
        preserving: actionError,
        allowsAutomaticAgentUpdate: false,
        expectedPreviousAgentInstanceID: previousAgentInstanceID
      )
    }
  }

  private func showAgentReplacementInProgress(descriptor: ServiceDescriptor) {
    let message = switch descriptor.replacementPhase {
    case .committed:
      """
      A KeyboardLocker agent replacement has been committed. New lock requests remain \
      blocked while its coordinator finishes and the old agent exits. If this state \
      persists, restart macOS; another app instance cannot safely take over an unregister \
      that may still be in flight.
      """

    case .prepared:
      """
      A KeyboardLocker agent replacement is being prepared. New lock requests remain \
      blocked until its coordinator commits or the short preparation expires.
      """

    default:
      """
      The KeyboardLocker agent reports a replacement state this app does not recognize. \
      New lock requests remain blocked to protect the current lock state. Update the app, \
      or restart macOS if this state persists.
      """
    }

    pendingUpdatePlan = nil
    stopStateObservation()
    clearAgentDetail(reason: message)
    state = .agentReplacementInProgress(message: message)
    lastError = nil
    reconciliationTask?.cancel()
    reconciliationTask = Task { [weak self] in
      do {
        try await Task.sleep(for: Self.replacementProgressPollInterval)
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      self?.startReconciliation(allowsAutomaticAgentUpdate: false)
    }
  }

  private func showAgentUpdateRequired(plan: AgentUpdatePlan) {
    pendingUpdatePlan = plan
    // An agent needing an update may not implement the settings-write selector at all, so the
    // settings UI must not present an editable configuration until the handshake succeeds again.
    clearAgentDetail(reason: plan.message)
    state = .agentUpdateRequired(
      isLocked: plan.isLocked,
      message: plan.message
    )
    lastError = nil
    if plan.canReadLockState {
      startStateObservation()
    } else {
      stopStateObservation()
    }
  }

  private func showServiceFailure(_ error: Error, context: String? = nil) async {
    guard !Task.isCancelled else {
      return
    }
    stopStateObservation()

    if let clientError = error as? XPCClientError,
       case .peerAuthenticationUnavailable = clientError {
      pendingUpdatePlan = nil
      clearAgentDetail(reason: clientError.localizedDescription)
      state = .unavailable(
        message: """
        This copy of KeyboardLocker cannot establish its signed XPC identity. \
        \(clientError.localizedDescription) Install and run the complete app bundle signed by \
        the configured Apple development team.
        """,
        canRestartAgent: false
      )
      lastError = nil
      return
    }

    // An XPC failure can mean the user disabled the Agent while the App was running.
    let currentRegistrationState = lifecycle.ensureEnabled()
    guard !Task.isCancelled else {
      return
    }

    if applyRegistrationState(currentRegistrationState) {
      pendingUpdatePlan = nil
      clearAgentDetail(reason: error.localizedDescription)
      let contextMessage = context.map { " \($0)" } ?? ""
      state = .unavailable(
        message: """
        The KeyboardLocker agent is enabled but could not be reached. \
        \(error.localizedDescription)\(contextMessage)
        """,
        canRestartAgent: true
      )
      lastError = nil
    }
  }

  /// Returns `true` only when XPC readiness checks should continue.
  private func applyRegistrationState(_ registrationState: AgentRegistrar.State) -> Bool {
    switch registrationState {
    case .enabled:
      return true

    case .approvalRequired:
      stopStateObservation()
      pendingUpdatePlan = nil
      clearAgentDetail(
        reason: "The KeyboardLocker agent needs approval in Login Items before it can be reached."
      )
      state = .agentApprovalRequired
      lastError = nil
      return false

    case let .unavailable(failure):
      stopStateObservation()
      pendingUpdatePlan = nil
      clearAgentDetail(reason: failure.message)
      let canRestartAgent = if case .restartFailed = failure {
        true
      } else {
        false
      }
      state = .unavailable(
        message: failure.message,
        canRestartAgent: canRestartAgent
      )
      lastError = nil
      return false
    }
  }

  private func receiveLockState(_ isLocked: Bool) {
    if activity != nil {
      return
    }

    switch state {
    case .ready:
      state = .ready(isLocked: isLocked)
      lastError = nil

    case .accessibilityRequired:
      state = .accessibilityRequired(isLocked: isLocked)
      lastError = nil

    case .agentUpdateRequired:
      if let pendingUpdatePlan,
         pendingUpdatePlan.canReadLockState {
        let updatedPlan = pendingUpdatePlan.updatingLockState(isLocked)
        self.pendingUpdatePlan = updatedPlan
        state = .agentUpdateRequired(
          isLocked: isLocked,
          message: updatedPlan.message
        )
        lastError = nil
      }

    case .checking:
      needsFollowUpReconciliation = true
      state = .checking(lastKnownLock: isLocked)

    case .agentApprovalRequired, .agentReplacementInProgress, .unavailable:
      reconcile()
    }
  }

  /// Fetches the authoritative lock snapshot and the persisted settings once the handshake has
  /// established that the Agent is reachable and compatible.
  ///
  /// Kept out of `AgentReadinessCoordinator`: readiness decides whether the Agent can be trusted at
  /// all, while this is presentation detail whose failure must not downgrade a ready state.
  private func startAgentDetailRefresh() {
    agentDetailTask?.cancel()
    agentDetailTask = Task { [weak self] in
      guard let self else {
        return
      }

      do {
        let snapshot = try await client.lockStatusSnapshot()
        guard !Task.isCancelled else {
          return
        }
        lockSnapshot = snapshot
      } catch {
        guard !Task.isCancelled else {
          return
        }
        lockSnapshot = nil
      }

      do {
        let settings = try await client.currentSettings()
        guard !Task.isCancelled else {
          return
        }
        settingsState = .loaded(settings)
      } catch {
        guard !Task.isCancelled else {
          return
        }
        settingsState = .unavailable(error.localizedDescription)
      }
    }
  }

  /// Drops presentation detail whenever the Agent stops being a trustworthy source for it.
  ///
  /// Settings become explicitly unavailable rather than falling back to `.default`, which would
  /// show the user a configuration the Agent is not actually using.
  private func clearAgentDetail(reason: String) {
    agentDetailTask?.cancel()
    agentDetailTask = nil
    lockSnapshot = nil
    settingsState = .unavailable(reason)
  }

  private func startStateObservation() {
    guard stateToken == nil else {
      return
    }

    stateToken = lockStateObserver.subscribe(initialState: state.knownLockState) { [weak self] isLocked in
      self?.receiveLockState(isLocked)
    }
  }

  private func stopStateObservation() {
    stateToken = nil
  }

  private func publishSnapshotIfNeeded(force: Bool = false) {
    let currentSnapshot = snapshot
    guard force || currentSnapshot != lastPublishedSnapshot else {
      return
    }

    lastPublishedSnapshot = currentSnapshot
    onSnapshotChange?(currentSnapshot)
  }
}

private enum AgentUpdateError: Error, LocalizedError {
  case agentDidNotRestart

  var errorDescription: String? {
    switch self {
    case .agentDidNotRestart:
      "The KeyboardLocker agent did not restart into a new process."
    }
  }
}

private enum SafetyCheckError: Error, LocalizedError {
  case lockAlreadyActive

  var errorDescription: String? {
    switch self {
    case .lockAlreadyActive:
      "The safety check did not start because the keyboard was already locked. Unlock it and try again."
    }
  }
}
