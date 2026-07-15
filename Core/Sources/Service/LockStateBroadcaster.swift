import Common
import Foundation

// MARK: - Lock State Broadcaster

/// Broadcasts lock state changes via system notifications.
///
/// Call `broadcast(isLocked:)` from the Agent process after lock state changes. Only
/// **long-lived, state-reflecting** surfaces (App menu bar, Widgets) need this — they subscribe
/// via `LockStateSubscriber`. One-shot surfaces (CLI queries, AppleScript, Shortcuts) read the
/// authoritative state directly with a `status` XPC call and are synchronized by construction.
///
/// Both channels carry no meaningful payload for consumers — subscribers fetch the authoritative
/// state from the Agent on any signal. Two channels are posted for delivery robustness:
/// - **Darwin**: can wake an App-Napped / suspended process so it learns of changes made while idle.
/// - **Distributed**: delivered on the main queue; the reliable path for a running CFRunLoop.
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
