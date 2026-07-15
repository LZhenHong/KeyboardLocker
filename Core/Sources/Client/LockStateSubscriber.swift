import Common
import Foundation

// MARK: - Lock State Subscriber

/// Subscribes to lock state changes via DistributedNotification.
///
/// Use this in App/CLI processes to receive state changes from the Agent.
/// The Agent broadcasts changes using `LockStateBroadcaster`.
public enum LockStateSubscriber {
  public typealias StateChangeHandler = (Bool) -> Void

  /// Subscribes to lock state changes.
  /// Returns a token that must be retained; subscription is cancelled when token is deallocated.
  public static func subscribe(_ handler: @escaping StateChangeHandler) -> ObserverToken {
    let observer = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(NotificationNames.stateChanged),
      object: nil,
      queue: .main
    ) { notification in
      if let isLocked = notification.userInfo?["isLocked"] as? Bool {
        handler(isLocked)
      }
    }

    return ObserverToken {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
  }

  /// Lock state changes as an `AsyncStream`. The subscription lives for the stream's lifetime
  /// and is torn down automatically when the consuming task is cancelled.
  public static var stateChanges: AsyncStream<Bool> {
    AsyncStream { continuation in
      let token = subscribe { continuation.yield($0) }
      continuation.onTermination = { _ in
        // Retain the token until termination, then release to unsubscribe.
        _ = token
      }
    }
  }
}

// MARK: - Observer Token

/// Token that controls subscription lifecycle.
/// Subscription is automatically cancelled when token is deallocated.
public final class ObserverToken {
  private let onDeinit: () -> Void

  public init(onDeinit: @escaping () -> Void) {
    self.onDeinit = onDeinit
  }

  deinit {
    onDeinit()
  }
}
