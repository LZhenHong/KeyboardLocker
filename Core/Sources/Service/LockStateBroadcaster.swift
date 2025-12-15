import Common
import Foundation

// MARK: - Lock State Broadcaster

/// Broadcasts lock state changes via system notifications.
///
/// Call `broadcast(isLocked:)` from the Agent process after lock state changes.
/// Clients subscribe using `LockStateSubscriber` in the Client module.
///
/// Notification channels:
/// - **Darwin**: Lightweight system-wide (no payload). For CLI, scripts, Shortcuts.
/// - **Distributed**: With state payload. For widgets, extensions, other apps.
public enum LockStateBroadcaster {
  /// Broadcasts lock state change to all system notification channels.
  public static func broadcast(isLocked: Bool) {
    postDarwin()
    postDistributed(isLocked: isLocked)
  }

  private static func postDarwin() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(NotificationNames.stateChanged as CFString),
      nil,
      nil,
      true
    )
  }

  private static func postDistributed(isLocked: Bool) {
    DistributedNotificationCenter.default().post(
      name: Notification.Name(NotificationNames.stateChanged),
      object: nil,
      userInfo: ["isLocked": isLocked]
    )
  }
}
