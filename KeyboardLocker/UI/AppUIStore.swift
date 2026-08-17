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

  func startSafetyCheck() {
    coordinator.startSafetyCheck()
  }
}
