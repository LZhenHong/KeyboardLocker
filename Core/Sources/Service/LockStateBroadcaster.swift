import Common
import Foundation

// MARK: - Lock State Broadcaster

/// Broadcasts lock state changes via system notifications.
///
/// Call `broadcast()` from the Agent process after lock state changes. Only
/// **long-lived, state-reflecting** surfaces (App menu bar, Widgets) need this — they subscribe
/// via `LockStateSubscriber`. One-shot surfaces (CLI queries, AppleScript, Shortcuts) read the
/// authoritative state directly with a `status` XPC call and are synchronized by construction.
///
/// Both channels are payload-free "something changed" signals — subscribers fetch the
/// authoritative state from the Agent on any signal, never trusting a notification's contents.
/// Two channels are posted for delivery robustness:
/// - **Darwin**: can wake an App-Napped / suspended process so it learns of changes made while idle.
/// - **Distributed**: delivered on the main queue; the reliable path for a running CFRunLoop.
public enum LockStateBroadcaster {
  /// Broadcasts a lock state change to all system notification channels.
  public static func broadcast() {
    postDarwin()
    postDistributed()
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

  private static func postDistributed() {
    DistributedNotificationCenter.default().post(
      name: Notification.Name(NotificationNames.stateChanged),
      object: nil
    )
  }
}
