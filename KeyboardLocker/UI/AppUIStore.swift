import Client
import Combine
import Foundation
import SwiftUI

/// Publishes `AppCoordinator` snapshots to SwiftUI and forwards user intent back.
///
/// Deliberately holds no domain logic and no lock or settings state of its own: everything it
/// exposes is derived from the coordinator's latest published snapshot, so the views cannot drift
/// from the Agent's authoritative state.
///
/// `ObservableObject` rather than `@Observable` because the app deploys to macOS 13.
@MainActor
final class AppUIStore: ObservableObject {
  @Published private(set) var snapshot: AppCoordinator.Snapshot

  private let coordinator: AppCoordinator

  init(coordinator: AppCoordinator) {
    self.coordinator = coordinator
    snapshot = coordinator.snapshot
  }

  /// Accepts a coordinator snapshot from whoever owns the coordinator's single observer slot.
  ///
  /// The store deliberately does not install itself as that observer: the status menu owns it, and
  /// two presentations competing for one slot would silently leave one of them stale.
  func receive(_ snapshot: AppCoordinator.Snapshot) {
    self.snapshot = snapshot
  }

  // MARK: - Derived presentation state

  var isBusy: Bool {
    snapshot.activity != nil
  }

  /// The settings the user is editing: the Agent's persisted configuration, never a local default.
  var editableSettings: KeyboardLockerSettings? {
    snapshot.settingsState.settings
  }

  var settingsUnavailableMessage: String? {
    guard case let .unavailable(message) = snapshot.settingsState else {
      return nil
    }
    return message
  }

  /// What a running lock is enforcing right now, which can differ from `editableSettings` after a
  /// write landed during that lock.
  var activeSettings: KeyboardLockerSettings? {
    snapshot.lockSnapshot?.settings
  }

  var isLocked: Bool {
    snapshot.state.knownLockState ?? false
  }

  var autoUnlockDeadline: Date? {
    snapshot.lockSnapshot?.autoUnlockTargetDate
  }

  var lockStartDate: Date? {
    snapshot.lockSnapshot?.startedAt
  }

  /// How the most recent lock generation ended, straight from the Agent's snapshot.
  /// Presentation and diagnostics only; it never feeds a decision.
  var lastUnlock: UnlockRecord? {
    snapshot.lockSnapshot?.lastUnlock
  }

  /// The statistics page's history state, loaded on demand when the page appears.
  var historyState: AppCoordinator.HistoryState {
    snapshot.historyState
  }

  /// Aggregates derived from the loaded entries; nil until history lands.
  var historyStats: LockHistoryStats? {
    guard case let .loaded(entries) = snapshot.historyState else {
      return nil
    }
    return LockHistoryStats.compute(entries: entries, now: Date())
  }

  var canEditSettings: Bool {
    editableSettings != nil && !isBusy
  }

  /// Whether the primary lock/unlock control should be offered at all.
  var canPerformLockAction: Bool {
    guard !isBusy else {
      return false
    }
    switch snapshot.state {
    case .ready:
      return true
    case .accessibilityRequired(isLocked: true),
         .checking(lastKnownLock: true):
      // Unlock must stay reachable even when the agent is otherwise degraded.
      return true
    case let .agentUpdateRequired(isLocked, _):
      return isLocked == true
    case .accessibilityRequired, .agentApprovalRequired, .agentReplacementInProgress, .checking,
         .unavailable:
      return false
    }
  }

  /// The one recovery action the current degraded state calls for, or `nil` when the state is a
  /// normal ready/checking/in-progress one that needs no extra button.
  ///
  /// This is pure presentation routing over `AppCoordinator.State`; the actual work (each of which
  /// needs an AppKit confirmation or a System Settings jump) is carried by `PopoverActions`.
  enum RecoveryAction: Equatable {
    case openLoginItems
    case grantAccessibility
    case openAccessibilitySettings
    case updateAgent
    case restartAgent
  }

  var recoveryActions: [RecoveryAction] {
    guard !isBusy else {
      return []
    }
    switch snapshot.state {
    case .agentApprovalRequired:
      return [.openLoginItems]
    case .accessibilityRequired:
      return [.grantAccessibility, .openAccessibilitySettings]
    case .agentUpdateRequired:
      return [.updateAgent]
    case let .unavailable(_, canRestartAgent):
      return canRestartAgent ? [.restartAgent] : []
    case .agentReplacementInProgress, .checking, .ready:
      return []
    }
  }

  /// Whether the timed quick-lock actions belong in the current state: only a healthy unlocked
  /// agent can honor the override, and while locked it could not touch the running lock anyway.
  var canPerformTimedLock: Bool {
    guard !isBusy, case .ready(isLocked: false) = snapshot.state else {
      return false
    }
    return true
  }

  /// Whether the first-run safety check button belongs in the current state.
  var canRunSafetyCheck: Bool {
    guard !isBusy, snapshot.safetyCheckState != .running else {
      return false
    }
    if case .ready(isLocked: false) = snapshot.state {
      return true
    }
    return false
  }

  // MARK: - Actions

  func reconcile() {
    coordinator.reconcile()
  }

  func performDisplayedLockAction() {
    coordinator.performDisplayedLockAction()
  }

  func applySettings(_ settings: KeyboardLockerSettings) {
    coordinator.applySettings(settings)
  }

  func requestAccessibilityPermission() {
    coordinator.requestAccessibilityPermission()
  }

  func performTimedLock(seconds: TimeInterval) {
    coordinator.performTimedLock(seconds: seconds)
  }

  func loadLockHistory() {
    coordinator.loadLockHistory()
  }

  func startSafetyCheck() {
    coordinator.startSafetyCheck()
  }

  func updateAgent() {
    coordinator.updateAgent()
  }

  func restartAgent() {
    coordinator.restartAgent()
  }
}
