import Foundation

struct UnlockWaiter: Sendable {
  typealias CancelPolling = @Sendable () -> Void
  typealias PollUntilUnlocked = @Sendable () async throws -> Void

  private let cancelPolling: CancelPolling
  private let pollUntilUnlocked: PollUntilUnlocked
  private let stateChanges: AsyncStream<Bool>

  init(
    stateChanges: AsyncStream<Bool>,
    pollUntilUnlocked: @escaping PollUntilUnlocked,
    cancelPolling: @escaping CancelPolling
  ) {
    self.stateChanges = stateChanges
    self.pollUntilUnlocked = pollUntilUnlocked
    self.cancelPolling = cancelPolling
  }

  func waitUntilUnlocked() async throws {
    try await withThrowingTaskGroup(of: ObservationResult.self) { group in
      group.addTask {
        for await isLocked in stateChanges {
          if !isLocked {
            return .unlocked
          }
        }
        return .observationEnded
      }

      group.addTask {
        try await withTaskCancellationHandler {
          try await pollUntilUnlocked()
        } onCancel: {
          // XPC reply continuations do not observe Swift task cancellation by themselves.
          // Invalidating this client's cached connection makes an in-flight status request
          // complete through its proxy error handler instead of delaying group teardown until
          // the response timeout.
          cancelPolling()
        }
        return .unlocked
      }

      defer {
        group.cancelAll()
      }

      while let result = try await group.next() {
        switch result {
        case .unlocked:
          return
        case .observationEnded:
          continue
        }
      }

      throw XPCClientError.serviceUnavailable
    }
  }

  private enum ObservationResult: Sendable {
    case observationEnded
    case unlocked
  }
}

struct UnlockStatusPoller: Sendable {
  typealias FetchStatus = @Sendable () async throws -> Bool
  typealias ResetConnection = @Sendable () -> Void
  typealias Sleep = @Sendable (Duration) async throws -> Void

  private let fetchStatus: FetchStatus
  private let maximumConsecutiveFailures: Int
  private let pollInterval: Duration
  private let resetConnection: ResetConnection
  private let sleep: Sleep

  init(
    pollInterval: Duration,
    maximumConsecutiveFailures: Int,
    fetchStatus: @escaping FetchStatus,
    resetConnection: @escaping ResetConnection,
    sleep: @escaping Sleep
  ) {
    precondition(maximumConsecutiveFailures > 0)
    self.pollInterval = pollInterval
    self.maximumConsecutiveFailures = maximumConsecutiveFailures
    self.fetchStatus = fetchStatus
    self.resetConnection = resetConnection
    self.sleep = sleep
  }

  func waitUntilUnlocked() async throws {
    var consecutiveFailures = 0

    while true {
      try Task.checkCancellation()

      do {
        let isLocked = try await fetchStatus()
        if !isLocked {
          return
        }
        consecutiveFailures = 0
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        consecutiveFailures += 1
        resetConnection()
        if consecutiveFailures >= maximumConsecutiveFailures {
          throw error
        }
      }

      try await sleep(pollInterval)
    }
  }
}

extension XPCClient {
  /// Waits until the Agent reports that the global keyboard lock has been released.
  ///
  /// This observer does not own the lock. Notifications provide prompt updates, while periodic
  /// authoritative reads recover when notifications are lost or an Agent restart releases the
  /// event tap without broadcasting. Persistent query failures are surfaced instead of being
  /// misreported as an unlock.
  public func waitUntilUnlocked() async throws {
    let waiter = UnlockWaiter(
      stateChanges: LockStateSubscriber.stateChanges,
      pollUntilUnlocked: { [self] in
        try await pollUntilAuthoritativeUnlock()
      },
      cancelPolling: { [self] in
        resetConnection()
      }
    )
    try await waiter.waitUntilUnlocked()
  }

  private func pollUntilAuthoritativeUnlock() async throws {
    let poller = UnlockStatusPoller(
      pollInterval: .seconds(1),
      maximumConsecutiveFailures: 3,
      fetchStatus: { [self] in
        try await status()
      },
      resetConnection: { [self] in
        resetConnection()
      },
      sleep: { interval in
        try await Task.sleep(for: interval)
      }
    )
    try await poller.waitUntilUnlocked()
  }
}
