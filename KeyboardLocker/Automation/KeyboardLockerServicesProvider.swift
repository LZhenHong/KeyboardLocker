import AppKit

/// AppKit invokes service handlers synchronously and marshals the `error` out-pointer back to
/// the requesting app — the Services channel is the only external entry point that can carry a
/// failure reason (the URL scheme has none). Execution itself is async (the serial XPC chain),
/// so each handler waits, with a bound, for the outcome and reports it here; the in-app failure
/// alert is presented as before.
final nonisolated class KeyboardLockerServicesProvider: NSObject, @unchecked Sendable {
  /// Outlasts the worst-case Client mutation: the initial 5s XPC reply window plus the
  /// idempotent-retry window, with margin.
  private static let defaultWaitTimeout: TimeInterval = 15

  private let submit: @Sendable (ExternalAutomationAction) async -> ExternalAutomationFailure?
  private let waitTimeout: TimeInterval

  init(
    waitTimeout: TimeInterval = KeyboardLockerServicesProvider.defaultWaitTimeout,
    submit: @escaping @Sendable (ExternalAutomationAction) async -> ExternalAutomationFailure?
  ) {
    self.waitTimeout = waitTimeout
    self.submit = submit
  }

  @objc(lockKeyboard:userData:error:)
  nonisolated func lockKeyboard(
    _: NSPasteboard,
    userData _: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    perform(.lock, error: error)
  }

  @objc(unlockKeyboard:userData:error:)
  nonisolated func unlockKeyboard(
    _: NSPasteboard,
    userData _: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    perform(.unlock, error: error)
  }

  @objc(showKeyboardLockStatus:userData:error:)
  nonisolated func showKeyboardLockStatus(
    _: NSPasteboard,
    userData _: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    perform(.status, error: error)
  }

  private func perform(
    _ action: ExternalAutomationAction,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    let completion = ServicesRequestCompletion()
    let submit = submit
    Task {
      let failure = await submit(action)
      completion.complete(failureMessage: failure?.message)
    }

    switch completion.awaitOutcome(timeout: waitTimeout) {
    case .succeeded:
      break
    case let .failed(message):
      error.pointee = message as NSString
    case .timedOut:
      error.pointee = """
        KeyboardLocker did not finish the service request within \(Int(waitTimeout)) seconds; \
        it may still complete.
        """ as NSString
    }
  }
}

/// One-shot cell carrying a service request's outcome back to the thread AppKit blocked on the
/// handler.
private final class ServicesRequestCompletion: @unchecked Sendable {
  enum Outcome: Equatable {
    case succeeded
    case failed(String)
    case timedOut
  }

  private let semaphore = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var outcome: Outcome?

  func complete(failureMessage: String?) {
    let outcome: Outcome = failureMessage.map(Outcome.failed) ?? .succeeded
    lock.withLock { self.outcome = outcome }
    semaphore.signal()
  }

  func awaitOutcome(timeout: TimeInterval) -> Outcome {
    if Thread.isMainThread {
      // The execution chain is main-actor; blocking the main thread outright would starve the
      // very work being awaited. Pump the run loop — like a modal session — so it can proceed.
      let deadline = Date().addingTimeInterval(timeout)
      while Date() < deadline, lock.withLock({ outcome }) == nil {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
      }
    } else {
      _ = semaphore.wait(timeout: .now() + timeout)
    }
    return lock.withLock { outcome } ?? .timedOut
  }
}
