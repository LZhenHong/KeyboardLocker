import Foundation

/// Signal-observer seam for the interactive-lock wait path, injectable so tests can assert
/// installation and cancellation without touching process signal state.
protocol KlockTerminationGuarding {
  /// Observes the covered termination signals and returns a cancellation closure for the
  /// normal completion path. `onTermination` receives the caught signal number.
  func install(onTermination: @escaping (Int32) -> Void) -> () -> Void
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
