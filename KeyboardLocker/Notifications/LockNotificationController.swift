import Client
import Foundation
import UserNotifications

/// Notification-center surface used by `LockNotificationController`.
/// The live implementation wraps `UNUserNotificationCenter`; tests drive a recording fake.
/// Class-constrained so the controller can install its action handler on a `let` reference.
@MainActor
protocol LockNotificationServing: AnyObject, Sendable {
  /// Invoked (from any thread) when the user chooses the notification's Unlock Now action.
  var actionHandler: (@Sendable (String) -> Void)? { get set }
  /// Registers the locked category and its action with the system.
  func installUnlockActionCategory()
  /// Asks the system for permission to post alerts. This surface degrades silently on denial.
  func requestAuthorization() async -> Bool
  /// Whether the app may currently deliver user-visible notifications.
  func canPost() async -> Bool
  /// Posts the locked notification immediately; a repeated identifier replaces the previous one.
  func postLocked(identifier: String, categoryIdentifier: String, title: String, body: String)
  /// Removes the locked notification from Notification Center and any pending delivery.
  func removeLocked(identifier: String)
}

/// Presentation-only wrapper: while the App observes the keyboard as locked it keeps a single
/// notification on screen whose Unlock Now action performs an idempotent desired-state unlock.
/// The notification never carries authoritative state; its content is a presentation cache
/// refreshed from the Agent's snapshot on every locked signal.
@MainActor
final class LockNotificationController {
  static let notificationIdentifier = "keyboard-locked"
  static let categoryIdentifier = "KEYBOARD_LOCKED"
  static let unlockActionIdentifier = "UNLOCK_NOW"

  private let notifications: any LockNotificationServing
  private let lockStateObserver: any AgentLockStateObserving
  private let snapshotQuery: @Sendable () async throws -> LockStatusSnapshot
  private let unlock: @Sendable () async throws -> Void
  private var stateToken: ObserverToken?
  private var tail: Task<Void, Never>?

  init(
    notifications: any LockNotificationServing,
    lockStateObserver: any AgentLockStateObserving,
    snapshotQuery: @escaping @Sendable () async throws -> LockStatusSnapshot,
    unlock: @escaping @Sendable () async throws -> Void
  ) {
    self.notifications = notifications
    self.lockStateObserver = lockStateObserver
    self.snapshotQuery = snapshotQuery
    self.unlock = unlock
    notifications.actionHandler = { @Sendable actionIdentifier in
      Task { @MainActor [weak self] in
        self?.handleAction(actionIdentifier)
      }
    }
  }

  func start() {
    notifications.installUnlockActionCategory()
    // Long-lived wrapper form: subscribe to the signal, then re-query for presentation content.
    // The subscription outlives the controller via the App delegate's ownership.
    stateToken = lockStateObserver.subscribe(initialState: nil) { [weak self] isLocked in
      self?.handleLockStateChange(isLocked)
    }
    enqueue { [notifications] in
      _ = await notifications.requestAuthorization()
    }
  }

  private func handleLockStateChange(_ isLocked: Bool) {
    if isLocked {
      enqueue { [weak self] in
        await self?.postLockedNotification()
      }
    } else {
      enqueue { [notifications] in
        notifications.removeLocked(identifier: LockNotificationController.notificationIdentifier)
      }
    }
  }

  /// Internal so tests can drive action delivery deterministically; production reaches it only
  /// through the notification delegate's `actionHandler` hop.
  func handleAction(_ actionIdentifier: String) {
    guard actionIdentifier == Self.unlockActionIdentifier else {
      return
    }
    // Desired-state unlock is idempotent; on failure the lock (and its notification) stays.
    enqueue { [weak self] in
      try? await self?.unlock()
    }
  }

  private func postLockedNotification() async {
    guard await notifications.canPost() else {
      return
    }
    // The action remains valid without snapshot details: it re-proves state at the Agent.
    let snapshot = try? await snapshotQuery()
    notifications.postLocked(
      identifier: Self.notificationIdentifier,
      categoryIdentifier: Self.categoryIdentifier,
      title: "Keyboard Locked",
      body: Self.makeBody(snapshot: snapshot)
    )
  }

  private static func makeBody(snapshot: LockStatusSnapshot?) -> String {
    guard let snapshot else {
      return "Choose Unlock Now to unlock."
    }
    var lines = ["Press \(snapshot.settings.unlockHotkey.displayString) or choose Unlock Now."]
    if let target = snapshot.autoUnlockTargetDate {
      lines.append("Auto-unlocks at \(target.formatted(date: .omitted, time: .shortened)).")
    }
    return lines.joined(separator: " ")
  }

  /// Serializes notification work so a quick lock/unlock flip can never post after the removal.
  private func enqueue(_ work: @escaping @MainActor () async -> Void) {
    let previous = tail
    tail = Task { @MainActor in
      await previous?.value
      await work()
    }
  }

  /// Test support: waits for queued notification work to settle.
  func waitUntilIdle() async {
    await tail?.value
  }
}

/// Production `LockNotificationServing` backed by `UNUserNotificationCenter`.
@MainActor
final class LiveLockNotificationService: LockNotificationServing {
  private let center: UNUserNotificationCenter
  private let delegateBridge: NotificationDelegateBridge

  var actionHandler: (@Sendable (String) -> Void)? {
    get {
      delegateBridge.actionHandler
    }
    set {
      delegateBridge.actionHandler = newValue
    }
  }

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
    delegateBridge = NotificationDelegateBridge()
    // Installed during App-delegate init — before launch completes — so an Unlock Now response
    // that relaunched the App is still delivered.
    center.delegate = delegateBridge
  }

  func installUnlockActionCategory() {
    let unlockAction = UNNotificationAction(
      identifier: LockNotificationController.unlockActionIdentifier,
      title: "Unlock Now"
    )
    let category = UNNotificationCategory(
      identifier: LockNotificationController.categoryIdentifier,
      actions: [unlockAction],
      intentIdentifiers: []
    )
    center.setNotificationCategories([category])
  }

  func requestAuthorization() async -> Bool {
    (try? await center.requestAuthorization(options: [.alert])) ?? false
  }

  func canPost() async -> Bool {
    let settings = await center.notificationSettings()
    return switch settings.authorizationStatus {
    case .authorized, .provisional:
      true
    case .denied, .notDetermined:
      false
    @unknown default:
      false
    }
  }

  func postLocked(identifier: String, categoryIdentifier: String, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = categoryIdentifier
    // A nil trigger delivers immediately; the fixed identifier replaces the previous copy.
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    center.add(request, withCompletionHandler: nil)
  }

  func removeLocked(identifier: String) {
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
  }
}

/// `UNUserNotificationCenter.delegate` is weak and its callbacks are nonisolated; this bridge
/// owns the Objective-C surface and forwards the Unlock Now action to the main actor.
private final class NotificationDelegateBridge: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  var actionHandler: (@Sendable (String) -> Void)?

  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let actionIdentifier = response.actionIdentifier
    if actionIdentifier != UNNotificationDefaultActionIdentifier,
       actionIdentifier != UNNotificationDismissActionIdentifier {
      actionHandler?(actionIdentifier)
    }
    completionHandler()
  }

  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    willPresent _: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // The App is a menu-bar accessory; show the banner even while it is active.
    completionHandler([.banner, .list])
  }
}
