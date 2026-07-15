import Common
import Foundation
import os

// MARK: - Lock State Subscriber

/// Subscribes to lock state changes broadcast by the Agent (`LockStateBroadcaster`).
///
/// Two channels are observed for robustness, and **both converge on the same behavior**:
/// on any signal, fetch the authoritative state from the Agent via `XPCClient.status()`
/// rather than trusting a notification payload (which can be dropped, delivered out of
/// order, or arrive stale).
///
/// - **Darwin** (`CFNotificationCenterGetDarwinNotifyCenter`): can wake an App-Napped /
///   suspended process, so a menu-bar app still learns of a lock started by the CLI while
///   it was idle. Payload-free by design.
/// - **Distributed**: retained because a pure async command-line tool (klock) does not
///   reliably run a CFRunLoop for Darwin callbacks; the distributed center delivers on the
///   main queue, which the CLI's async main drains.
///
/// Delivered values are de-duplicated, so redundant signals across the two channels surface
/// as at most one handler call per actual state change.
public enum LockStateSubscriber {
  public typealias StateChangeHandler = (Bool) -> Void

  private static let logger = Logger(subsystem: SharedConstants.machServiceName, category: "LockStateSubscriber")

  /// Subscribes to lock state changes.
  /// Returns a token that must be retained; subscription is cancelled when the token deallocates.
  public static func subscribe(_ handler: @escaping StateChangeHandler) -> ObserverToken {
    let reconciler = StateReconciler(handler: handler)

    let darwin = DarwinObserver(name: NotificationNames.stateChanged) {
      reconciler.signal()
    }

    let distributed = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(NotificationNames.stateChanged),
      object: nil,
      queue: .main
    ) { _ in
      reconciler.signal()
    }

    return ObserverToken {
      darwin.cancel()
      DistributedNotificationCenter.default().removeObserver(distributed)
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

// MARK: - State Reconciler

/// On each signal, fetches the Agent's authoritative lock state and forwards it to the handler
/// only when it differs from the last value delivered — collapsing duplicate cross-channel
/// signals into one handler call per real change.
private final class StateReconciler: @unchecked Sendable {
  private let handler: LockStateSubscriber.StateChangeHandler
  private let lock = OSAllocatedUnfairLock()
  private var lastDelivered: Bool?

  /// Transient XPC failures (e.g. the Agent being relaunched on demand) are retried so a real
  /// state change is never dropped just because one fetch raced a reconnect.
  private static let fetchAttempts = 3
  private static let retryDelay: Duration = .milliseconds(200)

  init(handler: @escaping LockStateSubscriber.StateChangeHandler) {
    self.handler = handler
  }

  func signal() {
    Task { [weak self] in
      guard let self, let isLocked = await fetchState() else {
        return
      }

      let shouldDeliver: Bool = lock.withLock {
        guard lastDelivered != isLocked else {
          return false
        }
        lastDelivered = isLocked
        return true
      }

      guard shouldDeliver else {
        return
      }

      await MainActor.run { self.handler(isLocked) }
    }
  }

  private func fetchState() async -> Bool? {
    for attempt in 1 ... Self.fetchAttempts {
      if let isLocked = try? await XPCClient.shared.status() {
        return isLocked
      }
      if attempt < Self.fetchAttempts {
        try? await Task.sleep(for: Self.retryDelay)
      }
    }
    return nil
  }
}

// MARK: - Darwin Observer

/// RAII wrapper around a Darwin notification observer. The C callback cannot capture context,
/// so the observing instance is passed through the opaque observer pointer.
private final class DarwinObserver {
  private let name: CFNotificationName
  private let onNotify: () -> Void

  init(name: String, onNotify: @escaping () -> Void) {
    self.name = CFNotificationName(name as CFString)
    self.onNotify = onNotify

    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      observer,
      { _, observer, _, _, _ in
        guard let observer else { return }
        Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue().onNotify()
      },
      self.name.rawValue,
      nil,
      .deliverImmediately
    )
  }

  func cancel() {
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      name,
      nil
    )
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
