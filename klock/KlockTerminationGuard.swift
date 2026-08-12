import Foundation

/// Signal-observer seam for the interactive-lock wait path, injectable so tests can assert
/// installation and cancellation without touching process signal state.
protocol KlockTerminationGuarding {
  /// Observes the covered termination signals and returns a cancellation closure for the
  /// normal completion path. `onTermination` receives the caught signal number.
  func install(onTermination: @escaping (Int32) -> Void) -> () -> Void
}

/// Reconciles process termination with interactive acquisition and the subsequent unlock wait.
/// The first accepted signal owns the command result, so a concurrent normal wait completion can
/// never return success or failure before bounded signal cleanup finishes.
final class KlockInteractiveTerminationCoordinator: @unchecked Sendable {
  enum WaitResult {
    case failed(any Error)
    case signaled(Int32)
    case unlocked
  }

  typealias Cleanup = () async -> Void

  private enum Phase {
    case acquiring
    case acquired
    case finished
  }

  private struct State {
    var phase = Phase.acquiring
    var signal: Int32?
    var signalReady = false
    var waitContinuation: CheckedContinuation<WaitResult, Never>?
  }

  private static let cleanupTimeout: Duration = .seconds(2)

  private let cleanup: Cleanup
  private let lock = NSLock()
  private var state = State()

  init(cleanup: @escaping Cleanup) {
    self.cleanup = cleanup
  }

  /// Records only the first signal. During acquisition it remains disarmed until the Agent reply
  /// establishes whether cleanup may touch the global lock.
  func receive(signal: Int32) {
    let shouldStartCleanup = lock.withLock {
      guard state.phase != .finished, state.signal == nil else {
        return false
      }
      state.signal = signal
      guard state.phase == .acquired else {
        return false
      }
      return true
    }

    if shouldStartCleanup {
      Task { [self] in
        await finishSignal(signal)
      }
    }
  }

  /// Atomically closes an acquisition that did not create a lock. A signal already accepted in
  /// the acquisition window wins; otherwise later signals are ignored by the finished command.
  func resolveWithoutAcquisition() -> Int32? {
    lock.withLock {
      guard state.phase == .acquiring else {
        return nil
      }
      state.phase = .finished
      return state.signal.map { 128 + $0 }
    }
  }

  /// Arms cleanup after confirmed acquisition and handles a signal retained from the request.
  func resolveAcquired() async -> Int32? {
    let pendingSignal = lock.withLock { () -> Int32? in
      guard state.phase == .acquiring else {
        return nil
      }
      state.phase = .acquired
      guard let signal = state.signal else {
        return nil
      }
      return signal
    }

    guard let pendingSignal else {
      return nil
    }
    await waitForCleanupOrTimeout()
    lock.withLock { state.phase = .finished }
    return 128 + pendingSignal
  }

  /// Races the normal Agent wait against termination without structured-concurrency cancellation
  /// holding the command open. Once `receive(signal:)` accepts a signal, normal completion loses.
  func waitUntilUnlocked(
    _ operation: @escaping @Sendable () async throws -> Void
  ) async -> WaitResult {
    await withCheckedContinuation { continuation in
      let preparation = lock.withLock { () -> (WaitResult?, Bool) in
        guard state.phase == .acquired else {
          return (.unlocked, false)
        }
        if state.signalReady, let signal = state.signal {
          state.phase = .finished
          return (.signaled(128 + signal), false)
        }
        state.waitContinuation = continuation
        return (nil, state.signal == nil)
      }

      if let result = preparation.0 {
        continuation.resume(returning: result)
      } else if preparation.1 {
        Task { [self] in
          do {
            try await operation()
            finishWait(.unlocked)
          } catch {
            finishWait(.failed(error))
          }
        }
      }
    }
  }

  private func finishSignal(_ signal: Int32) async {
    await waitForCleanupOrTimeout()
    let continuation = lock.withLock { () -> CheckedContinuation<WaitResult, Never>? in
      state.signalReady = true
      guard let continuation = state.waitContinuation else {
        return nil
      }
      state.phase = .finished
      state.waitContinuation = nil
      return continuation
    }
    continuation?.resume(returning: .signaled(128 + signal))
  }

  private func finishWait(_ result: WaitResult) {
    let continuation = lock.withLock { () -> CheckedContinuation<WaitResult, Never>? in
      guard state.phase == .acquired, state.signal == nil else {
        return nil
      }
      state.phase = .finished
      defer { state.waitContinuation = nil }
      return state.waitContinuation
    }
    continuation?.resume(returning: result)
  }

  /// Returns as soon as cleanup completes or after the hard deadline. The losing unstructured
  /// task may finish later, but `CleanupWaiter` makes continuation resumption one-shot.
  private func waitForCleanupOrTimeout() async {
    await withCheckedContinuation { continuation in
      let waiter = CleanupWaiter(continuation: continuation)
      Task { [self] in
        await cleanup()
        waiter.finish()
      }
      Task {
        try? await Task.sleep(for: Self.cleanupTimeout)
        waiter.finish()
      }
    }
  }
}

private final class CleanupWaiter: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  init(continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }

  func finish() {
    let continuation = lock.withLock {
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

/// Watches SIGTERM/SIGHUP/SIGINT via GCD signal sources, whose handlers run on a dispatch
/// queue and may therefore perform ordinary work (unlike raw `signal()` handlers).
///
/// SIGKILL/SIGSTOP cannot be observed by design; a lock orphaned that way is still reachable
/// through the Agent-side affordances (unlock hotkey, notification action, auto-unlock).
struct LiveKlockTerminationGuard: KlockTerminationGuarding {
  private static let coveredSignals: [Int32] = [SIGTERM, SIGHUP, SIGINT]

  func install(onTermination: @escaping (Int32) -> Void) -> () -> Void {
    let sources = Self.coveredSignals.map { signalNumber -> DispatchSourceSignal in
      // GCD signal delivery requires the default action to be ignored first.
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
      source.setEventHandler {
        onTermination(signalNumber)
      }
      source.resume()
      return source
    }
    return {
      sources.forEach { $0.cancel() }
    }
  }
}
