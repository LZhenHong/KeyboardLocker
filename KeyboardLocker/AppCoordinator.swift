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
  }

  enum Activity: Equatable {
    case locking
    case requestingAccessibility
    case restartingAgent
    case unlocking
    case updatingAgent
  }

  private(set) var state: State = .checking(lastKnownLock: nil)
  private(set) var activity: Activity?
  private(set) var lastError: String?

  private var reconciliationTask: Task<Void, Never>?
  private var needsFollowUpReconciliation = false
  private var pendingUpdatePlan: AgentUpdatePlan?
  private var attemptedAutomaticUpdateBuilds: Set<String> = []
  private var stateToken: ObserverToken?
  private let client: any AgentClientServing
  private let lifecycle: any AgentLifecycleServing
  private let readinessCoordinator: AgentReadinessCoordinator
  private let replacementCoordinator: AgentReplacementCoordinator

  private static let replacementProgressPollInterval: Duration = .seconds(3)

  convenience init() {
    self.init(
      client: LiveAgentClient(),
      lifecycle: LiveAgentLifecycle(),
      initialState: .checking(lastKnownLock: nil)
    )
    reconcile()
  }

  init(
    client: any AgentClientServing,
    lifecycle: any AgentLifecycleServing,
    initialState: State
  ) {
    self.client = client
    self.lifecycle = lifecycle
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

  func toggle() {
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

    let lastKnownLock: Bool? = switch state {
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
      state = .unavailable(message: failure.message, canRestartAgent: false)
      lastError = nil

    case let .ready(isLocked, hasAccessibilityPermission):
      pendingUpdatePlan = nil
      state = hasAccessibilityPermission
        ? .ready(isLocked: isLocked)
        : .accessibilityRequired(isLocked: isLocked)
      lastError = actionError
      startStateObservation()

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
         !attemptedAutomaticUpdateBuilds.contains(bundledBuild)
      {
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
      An Agent replacement has been committed. New lock requests remain blocked while its \
      coordinator finishes and the old Agent exits. If this state persists, restart macOS; \
      another app instance cannot safely take over an unregister that may still be in flight.
      """

    case .prepared:
      """
      An Agent replacement is being prepared. New lock requests remain blocked until its \
      coordinator commits or the short preparation expires.
      """

    default:
      """
      The Agent reports a replacement state this app does not recognize. New lock requests \
      remain blocked to protect the current lock state. Update the app, or restart macOS if \
      this state persists.
      """
    }

    pendingUpdatePlan = nil
    stopStateObservation()
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
       case .peerAuthenticationUnavailable = clientError
    {
      pendingUpdatePlan = nil
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
      let contextMessage = context.map { " \($0)" } ?? ""
      state = .unavailable(
        message: """
        The background agent is enabled but could not be reached. \
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
      state = .agentApprovalRequired
      lastError = nil
      return false

    case let .unavailable(failure):
      stopStateObservation()
      pendingUpdatePlan = nil
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
         pendingUpdatePlan.canReadLockState
      {
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

  private func startStateObservation() {
    guard stateToken == nil else {
      return
    }

    let initialState: Bool? = switch state {
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

    stateToken = LockStateSubscriber.subscribe(initialState: initialState) { [weak self] isLocked in
      self?.receiveLockState(isLocked)
    }
  }

  private func stopStateObservation() {
    stateToken = nil
  }
}

private enum AgentUpdateError: Error, LocalizedError {
  case agentDidNotRestart

  var errorDescription: String? {
    switch self {
    case .agentDidNotRestart:
      "The background agent did not restart into a new process."
    }
  }
}
