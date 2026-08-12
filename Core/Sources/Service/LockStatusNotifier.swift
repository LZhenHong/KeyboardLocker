import Common
import Foundation
import UserNotifications

/// Notification-center surface used by `LockStatusNotifier`. The live implementation wraps
/// `UNUserNotificationCenter`; tests drive a recording fake. Class-constrained so the notifier
/// can install its action handler on a `let` reference.
@MainActor
protocol LockStatusNotifying: AnyObject, Sendable {
  /// Invoked (from any thread) when the user chooses the notification's Unlock Now action.
  var actionHandler: (@Sendable (String) -> Void)? { get set }
  /// Registers the locked category and its action with the system.
  func installUnlockActionCategory()
  /// Returns whether the Agent may deliver a user-visible alert, requesting authorization on
  /// first use. A denied or silent-only status degrades to no notification without an error.
  func requestAlertAuthorization() async -> Bool
  /// Posts the locked notification immediately; a repeated identifier replaces the previous one.
  func postLocked(identifier: String, categoryIdentifier: String, title: String, body: String)
  /// Removes the locked notification from Notification Center and any pending delivery.
  func removeLocked(identifier: String)
}

/// Owns the single "Keyboard Locked" notification from inside the Agent process.
///
/// The lock's discoverability surface must live and die with the lock itself, and only the
/// Agent is guaranteed to be alive for the lock's whole lifetime — menu-bar App, CLI, or Focus
/// extension may come and go. Posting here also pairs delivery with removal on the same state
/// transition, so a stale notification cannot outlive the lock (an Agent that exits while
/// locked drops its event tap, and the next launch clears the leftover via `start()`).
///
/// The notification is a presentation-only convenience: it carries a presentation cache of the
/// unlock affordances, never authoritative state, and a denied authorization degrades silently.
@MainActor
public final class LockStatusNotifier {
  static let notificationIdentifier = "keyboard-locked"
  static let categoryIdentifier = "KEYBOARD_LOCKED"
  static let unlockActionIdentifier = "UNLOCK_NOW"

  /// Process-wide instance wired to the shared engine. Created lazily; `KeyboardLockerAgent`
  /// calls `start()` during bootstrap so the action category and stale-notification cleanup
  /// are in place before any lock can be created.
  public static let shared = LockStatusNotifier(
    notifications: LiveLockStatusNotificationService(),
    snapshot: { LockEngine.shared.statusSnapshot },
    unlock: { LockEngine.shared.unlock() }
  )

  private let notifications: any LockStatusNotifying
  private let snapshot: @MainActor () -> LockStatusSnapshot
  private let unlock: @MainActor () -> Void
  private var tail: Task<Void, Never>?

  init(
    notifications: any LockStatusNotifying,
    snapshot: @escaping @MainActor () -> LockStatusSnapshot,
    unlock: @escaping @MainActor () -> Void
  ) {
    self.notifications = notifications
    self.snapshot = snapshot
    self.unlock = unlock
    notifications.actionHandler = { @Sendable actionIdentifier in
      Task { @MainActor [weak self] in
        self?.handleAction(actionIdentifier)
      }
    }
  }

  /// Installs the action category and removes any notification left behind by a previous Agent
  /// generation — its exit already released the lock, so the leftover can only be stale.
  public func start() {
    notifications.installUnlockActionCategory()
    enqueue { [notifications] in
      notifications.removeLocked(identifier: LockStatusNotifier.notificationIdentifier)
    }
  }

  /// Engine state-change hook, invoked after the mutation completed so the snapshot read here
  /// already describes the new state.
  func lockStateDidChange() {
    if snapshot().isLocked {
      enqueue { [weak self] in
        await self?.postLockedNotification()
      }
    } else {
      enqueue { [notifications] in
        notifications.removeLocked(identifier: LockStatusNotifier.notificationIdentifier)
      }
    }
  }

  private func handleAction(_ actionIdentifier: String) {
    guard actionIdentifier == Self.unlockActionIdentifier else {
      return
    }
    // Desired-state unlock is idempotent; the engine's state-change hook removes the
    // notification once the unlock lands.
    unlock()
  }

  private func postLockedNotification() async {
    guard await notifications.requestAlertAuthorization() else {
      return
    }
    notifications.postLocked(
      identifier: Self.notificationIdentifier,
      categoryIdentifier: Self.categoryIdentifier,
      title: "Keyboard Locked",
      body: Self.makeBody(snapshot: snapshot())
    )
  }

  private static func makeBody(snapshot: LockStatusSnapshot) -> String {
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

/// Production `LockStatusNotifying` backed by `UNUserNotificationCenter`.
@MainActor
final class LiveLockStatusNotificationService: LockStatusNotifying {
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
    center.delegate = delegateBridge
  }

  func installUnlockActionCategory() {
    let unlockAction = UNNotificationAction(
      identifier: LockStatusNotifier.unlockActionIdentifier,
      title: "Unlock Now"
    )
    let category = UNNotificationCategory(
      identifier: LockStatusNotifier.categoryIdentifier,
      actions: [unlockAction],
      intentIdentifiers: []
    )
    center.setNotificationCategories([category])
  }

  func requestAlertAuthorization() async -> Bool {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .denied:
      return false
    case .notDetermined:
      return (try? await center.requestAuthorization(options: [.alert])) ?? false
    @unknown default:
      return false
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
}
