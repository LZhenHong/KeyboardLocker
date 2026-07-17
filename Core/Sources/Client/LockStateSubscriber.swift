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
/// Delivered values are de-duplicated, so the initial calibration is emitted at most once and
/// redundant signals across the two channels surface as at most one handler call per actual
/// state change.
public enum LockStateSubscriber {
  public typealias StateChangeHandler = (Bool) -> Void

  private static let logger = Logger(subsystem: SharedConstants.machServiceName, category: "LockStateSubscriber")

  /// Subscribes to the authoritative lock state.
  /// After observer installation, the handler receives the current state when it differs from
  /// `initialState`, then receives de-duplicated changes. Pass a trusted snapshot to avoid
  /// re-delivering it; the default `nil` always emits a successful initial calibration.
  /// A transiently failed initial calibration is retried on the next signal.
  /// Returns a token that must be retained; subscription is cancelled when the token deallocates.
  public static func subscribe(
    initialState: Bool? = nil,
    _ handler: @escaping StateChangeHandler
  ) -> ObserverToken {
    subscribe(
      initialState: initialState,
      fetchState: { try await XPCClient.shared.status() },
      handler
    )
  }

  static func subscribe(
    initialState: Bool? = nil,
    fetchState: @escaping StateReconciler.FetchState,
    _ handler: @escaping StateChangeHandler
  ) -> ObserverToken {
    let reconciler = StateReconciler(
      initialState: initialState,
      fetchState: fetchState,
      handler: handler
    )

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

    // Notifications are hints rather than a durable event log. Calibrate only after both
    // observers are installed so a state change racing this first fetch schedules a follow-up
    // pass instead of falling into a subscribe/snapshot gap.
    reconciler.signal()

    return ObserverToken {
      reconciler.cancel()
      darwin.cancel()
      DistributedNotificationCenter.default().removeObserver(distributed)
    }
  }

  /// The authoritative lock state as an `AsyncStream`, beginning with an initial calibration.
  /// The subscription lives for the stream's lifetime and is torn down automatically when the
  /// consuming task is cancelled.
  public static var stateChanges: AsyncStream<Bool> {
    AsyncStream { continuation in
      let token = subscribe(initialState: nil) { continuation.yield($0) }
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
final class StateReconciler: @unchecked Sendable {
  typealias FetchState = @Sendable () async throws -> Bool

  private let fetchState: FetchState
  private let handler: LockStateSubscriber.StateChangeHandler
  private let lock = OSAllocatedUnfairLock()
  private var lastDelivered: Bool?
  private var hasPendingSignal = false
  private var isReconciling = false
  private var isCancelled = false
  private var workerTask: Task<Void, Never>?

  /// Transient XPC failures (e.g. the Agent being relaunched on demand) are retried so a real
  /// state change is never dropped just because one fetch raced a reconnect.
  private static let fetchAttempts = 3
  private static let retryDelay: Duration = .milliseconds(200)

  init(
    initialState: Bool? = nil,
    fetchState: @escaping FetchState,
    handler: @escaping LockStateSubscriber.StateChangeHandler
  ) {
    lastDelivered = initialState
    self.fetchState = fetchState
    self.handler = handler
  }

  func signal() {
    lock.withLock {
      guard !isCancelled else {
        return
      }

      hasPendingSignal = true
      guard !isReconciling else {
        return
      }

      isReconciling = true
      // Create and retain the worker while holding the same lock that protects
      // `isReconciling`. The task's first state access blocks on this lock, so a completed
      // worker can never overwrite the handle of a newer active worker.
      workerTask = Task<Void, Never> { [weak self] in
        guard let self else {
          return
        }
        await reconcilePendingSignals()
      }
    }
  }

  func cancel() {
    let task: Task<Void, Never>? = lock.withLock {
      guard !isCancelled else {
        return nil
      }

      isCancelled = true
      hasPendingSignal = false
      defer { workerTask = nil }
      return workerTask
    }
    task?.cancel()
  }

  private func reconcilePendingSignals() async {
    while takePendingSignal() {
      guard let isLocked = await fetchAuthoritativeState() else {
        continue
      }

      await MainActor.run {
        let shouldDeliver: Bool = self.lock.withLock {
          guard !self.isCancelled,
                self.lastDelivered != isLocked
          else {
            return false
          }

          self.lastDelivered = isLocked
          return true
        }
        guard shouldDeliver else {
          return
        }

        self.handler(isLocked)
      }
    }
  }

  /// Atomically claims one pending pass. Clearing the worker flag in the same critical section
  /// prevents a signal from being stranded between the worker's final check and its exit.
  private func takePendingSignal() -> Bool {
    lock.withLock {
      guard !isCancelled else {
        isReconciling = false
        return false
      }

      guard hasPendingSignal else {
        isReconciling = false
        return false
      }

      hasPendingSignal = false
      return true
    }
  }

  private func fetchAuthoritativeState() async -> Bool? {
    for attempt in 1 ... Self.fetchAttempts {
      guard shouldContinue else {
        return nil
      }

      do {
        let isLocked = try await fetchState()
        return shouldContinue ? isLocked : nil
      } catch {
        guard attempt < Self.fetchAttempts,
              shouldContinue
        else {
          return nil
        }

        do {
          try await Task.sleep(for: Self.retryDelay)
        } catch {
          return nil
        }
      }
    }
    return nil
  }

  private var shouldContinue: Bool {
    guard !Task.isCancelled else {
      return false
    }

    return lock.withLock {
      !isCancelled
    }
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
///
/// The token is immutable and its teardown path is thread-safe, so releasing the final reference
/// from an `AsyncStream` termination callback is safe on any executor.
public final class ObserverToken: @unchecked Sendable {
  private let onDeinit: () -> Void

  public init(onDeinit: @escaping () -> Void) {
    self.onDeinit = onDeinit
  }

  deinit {
    onDeinit()
  }
}
