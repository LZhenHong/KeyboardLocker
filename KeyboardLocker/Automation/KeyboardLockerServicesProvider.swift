import AppKit

/// AppKit invokes service handlers synchronously and marshals the `error` out-pointer back to
/// the requesting app — the Services channel is the only external entry point that can carry a
/// failure reason (the URL scheme has none). Execution itself is async (the serial XPC chain),
/// so each handler waits, with a bound, for the outcome and reports it here. Failure presentation
/// is scheduled only after the out-pointer is populated, so a modal alert cannot delay the caller.
final nonisolated class KeyboardLockerServicesProvider: NSObject, @unchecked Sendable {
  /// Outlasts the worst-case Client mutation: the initial 5s XPC reply window plus the
  /// idempotent-retry window, with margin.
  private static let defaultWaitTimeout: TimeInterval = 15

  private let presentFailure: @MainActor @Sendable (ExternalAutomationFailure) -> Void
  private let submit: @Sendable (ExternalAutomationAction) async -> ExternalAutomationFailure?
  private let waitTimeout: TimeInterval

  init(
    waitTimeout: TimeInterval = KeyboardLockerServicesProvider.defaultWaitTimeout,
    presentFailure: @escaping @MainActor @Sendable (ExternalAutomationFailure) -> Void = {
      AppKitExternalAutomationPresenter().presentFailures([$0], source: .service)
    },
    submit: @escaping @Sendable (ExternalAutomationAction) async -> ExternalAutomationFailure?
  ) {
    self.presentFailure = presentFailure
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
    let presentFailure = presentFailure
    Task {
      let failure = await submit(action)
      if let failure = completion.complete(failure: failure) {
        Task { @MainActor in
          presentFailure(failure)
        }
      }
    }

    switch completion.awaitOutcome(timeout: waitTimeout) {
    case .succeeded:
      break
    case let .failed(failure):
      error.pointee = failure.message as NSString
    case .timedOut:
      error.pointee = """
        KeyboardLocker did not finish the service request within \(Int(waitTimeout)) seconds; \
        it may still complete.
        """ as NSString
    }

    if let failure = completion.publishResultChannel() {
      Task { @MainActor in
        presentFailure(failure)
      }
    }
  }
}

/// One-shot cell carrying a service request's outcome back to the thread AppKit blocked on the
/// handler.
private final class ServicesRequestCompletion: @unchecked Sendable {
  enum Outcome: Equatable {
    case succeeded
    case failed(ExternalAutomationFailure)
    case timedOut
  }

  private let semaphore = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var outcome: Outcome?
  private var resultChannelPublished = false
  private var presentationClaimed = false

  /// Returns a late failure only when the handler has already published its result channel.
  /// Exactly one caller can claim presentation.
  func complete(failure: ExternalAutomationFailure?) -> ExternalAutomationFailure? {
    let outcome: Outcome = failure.map(Outcome.failed) ?? .succeeded
    let failureToPresent = lock.withLock {
      self.outcome = outcome
      return claimFailureForPresentation()
    }
    semaphore.signal()
    return failureToPresent
  }

  /// Marks the Services error out-pointer as populated (or intentionally untouched on success).
  /// A failure that completed first is returned to the handler for deferred presentation.
  func publishResultChannel() -> ExternalAutomationFailure? {
    lock.withLock {
      resultChannelPublished = true
      return claimFailureForPresentation()
    }
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

  private func claimFailureForPresentation() -> ExternalAutomationFailure? {
    guard resultChannelPublished, !presentationClaimed,
          case let .failed(failure)? = outcome
    else {
      return nil
    }
    presentationClaimed = true
    return failure
  }
}
