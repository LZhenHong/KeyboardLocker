import Client
import Foundation

/// The Agent operations `klock` depends on, mirroring the `XPCClient` signatures one-to-one so
/// command execution can be driven by a fake in tests.
protocol KlockClientServing {
  func currentSettings() async throws -> KeyboardLockerSettings
  func lockInteractively() async throws -> LockRequestOutcome
  func lock() async throws
  func unlock() async throws
  func toggle() async throws -> Bool
  func status() async throws -> Bool
  func lockStatusSnapshot() async throws -> LockStatusSnapshot
  func waitUntilUnlocked() async throws
  func hasAccessibilityPermission() async throws -> Bool
  func requestAccessibilityPermission() async throws
}

extension XPCClient: KlockClientServing {}

// MARK: - CLI

enum KlockCLI {
  /// Production entry point: wires the real process arguments, the live Agent client, and the
  /// real stdout/stderr, then terminates the process with the command's exit code.
  static func run() async {
    let exitCode = await run(
      arguments: Array(CommandLine.arguments.dropFirst()),
      client: XPCClient.shared,
      printOut: { print($0) },
      printError: { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
    )
    exit(exitCode)
  }

  /// Testable core: runs one invocation and returns its exit code instead of calling `exit`.
  static func run(
    arguments: [String],
    client: any KlockClientServing,
    openKeyboardLockerApp: @escaping () throws -> Void = KlockAppOpener.openContainingApp,
    agentPoll: (attempts: Int, interval: Duration) = (attempts: 5, interval: .seconds(1)),
    accessPoll: (attempts: Int, interval: Duration) = (attempts: 30, interval: .seconds(1)),
    terminationGuard: any KlockTerminationGuarding = LiveKlockTerminationGuard(),
    printOut: (String) -> Void,
    printError: @escaping (String) -> Void
  ) async -> Int32 {
    let command: KlockCommand
    do {
      guard let parsedCommand = try KlockCommandLineParser.parse(arguments) else {
        printUsage(to: printOut)
        return ExitCode.success
      }
      command = parsedCommand
    } catch KlockCommandLineError.unknownCommand(let name) {
      reportError("Unknown command: \(name)", printError: printError)
      printUsage(to: printOut)
      return ExitCode.error
    } catch KlockCommandLineError.unexpectedArguments(let unexpected) {
      reportError(
        "Unexpected argument\(unexpected.count == 1 ? "" : "s"): \(unexpected.joined(separator: " "))",
        printError: printError
      )
      printUsage(to: printOut)
      return ExitCode.error
    } catch {
      // KlockCommandLineParser only throws KlockCommandLineError.
      return ExitCode.error
    }

    switch command {
    case .help:
      printUsage(to: printOut)
      return ExitCode.success

    case .version:
      return printVersion(printOut: printOut, printError: printError)

    case let .lock(wait):
      if wait {
        return await executeInteractiveLock(
          client: client,
          terminationGuard: terminationGuard,
          printOut: printOut,
          printError: printError
        )
      }
      return await executeNonInteractiveLock(client: client, printOut: printOut, printError: printError)

    case .unlock:
      return await executeUnlock(client: client, printOut: printOut, printError: printError)

    case .toggle:
      return await executeToggle(client: client, printOut: printOut, printError: printError)

    case .requestAccess:
      return await executeRequestAccess(
        client: client,
        accessPoll: accessPoll,
        printOut: printOut,
        printError: printError
      )

    case .registerAgent:
      return await executeRegisterAgent(
        client: client,
        openKeyboardLockerApp: openKeyboardLockerApp,
        agentPoll: agentPoll,
        printOut: printOut,
        printError: printError
      )

    case let .status(output):
      return await executeStatus(output: output, client: client, printOut: printOut, printError: printError)
    }
  }

  // MARK: - Commands

  private static func executeInteractiveLock(
    client: any KlockClientServing,
    terminationGuard: any KlockTerminationGuarding,
    printOut: (String) -> Void,
    printError: @escaping (String) -> Void
  ) async -> Int32 {
    let unlockHotkey: Result<String, Error>
    do {
      unlockHotkey = try await .success(
        client.currentSettings().unlockHotkey.displayString
      )
    } catch {
      unlockHotkey = .failure(error)
    }

    let outcome: LockRequestOutcome
    do {
      outcome = try await client.lockInteractively()
    } catch {
      reportFailure(error, printError: printError)
      return ExitCode.error
    }

    guard outcome == .acquired else {
      printOut("Already locked. This command did not create a new lock.")
      return ExitCode.success
    }

    // The wait below keeps this process responsible for the lock it just created: a covered
    // termination signal (terminal closed, kill) must release it rather than leave the keyboard
    // locked with no visible owner. Ctrl+C never reaches the process — the Agent consumes it
    // as an unlock gesture — so SIGINT is only a fallback for a tap that failed to engage.
    let cancelTerminationGuard = terminationGuard.install { signal in
      let finished = DispatchSemaphore(value: 0)
      Task {
        await Self.unlockBeforeTermination(client: client, printError: printError)
        finished.signal()
      }
      _ = finished.wait(timeout: .now() + .seconds(2))
      exit(128 + signal)
    }
    defer {
      cancelTerminationGuard()
    }

    switch unlockHotkey {
    case let .success(hotkey):
      printOut("Locked. Press \(hotkey) or Ctrl+C to unlock.")

    case let .failure(error):
      printOut("Locked. Press Ctrl+C to unlock, or run `klock unlock` from another Terminal.")
      reportWarning(
        "Could not read the configured unlock shortcut: \(error.localizedDescription)",
        printError: printError
      )
    }

    do {
      try await client.waitUntilUnlocked()
      printOut("Unlocked.")
      return ExitCode.success
    } catch {
      reportFailure(error, printError: printError)
      return ExitCode.error
    }
  }

  /// Best-effort release of the lock this command created, bounded by the caller so the
  /// process still exits when the Agent is unreachable. The wire protocol carries no
  /// generation token for interactive locks, so if this command's lock was already released
  /// and another wrapper re-locked while this process waited, cleanup releases that newer
  /// lock — permitted by the global-lock contract (any entry may unlock), and documented
  /// here so the approximation stays explicit. Internal (not private) so tests can drive
  /// it directly — production reaches it only via the signal handler.
  static func unlockBeforeTermination(
    client: any KlockClientServing,
    printError: (String) -> Void
  ) async {
    do {
      try await client.unlock()
      printError("Terminated; released the keyboard lock created by this command.")
    } catch {
      printError(
        "Terminated; could not release the keyboard lock (\(error.localizedDescription)). " +
          "Unlock with the configured hotkey or the notification's Unlock Now button."
      )
    }
  }

  private static func executeNonInteractiveLock(
    client: any KlockClientServing,
    printOut: (String) -> Void,
    printError: (String) -> Void
  ) async -> Int32 {
    do {
      try await client.lock()
      printOut("Locked.")
      return ExitCode.success
    } catch {
      reportFailure(error, printError: printError)
      return ExitCode.error
    }
  }

  private static func executeUnlock(
    client: any KlockClientServing,
    printOut: (String) -> Void,
    printError: (String) -> Void
  ) async -> Int32 {
    do {
      try await client.unlock()
      printOut("Unlocked.")
      return ExitCode.success
    } catch {
      reportFailure(error, printError: printError)
      return ExitCode.error
    }
  }

  private static func executeToggle(
    client: any KlockClientServing,
    printOut: (String) -> Void,
    printError: (String) -> Void
  ) async -> Int32 {
    do {
      let isLocked = try await client.toggle()
      printOut(isLocked ? "Locked." : "Unlocked.")
      return ExitCode.success
    } catch {
      reportFailure(error, printError: printError)
      return ExitCode.error
    }
  }

  /// Registers the background Agent by launching the containing App — only the App bundle can
  /// hand its launchd plist to `SMAppService`. The command then polls briefly so a terminal
  /// user learns immediately whether registration produced a reachable Agent.
  private static func executeRegisterAgent(
    client: any KlockClientServing,
    openKeyboardLockerApp: () throws -> Void,
    agentPoll: (attempts: Int, interval: Duration),
    printOut: (String) -> Void,
    printError: (String) -> Void
  ) async -> Int32 {
    if (try? await client.status()) != nil {
      printOut("The KeyboardLocker agent is already registered and reachable.")
      return ExitCode.success
    }

    do {
      try openKeyboardLockerApp()
    } catch {
      reportFailure(error, printError: printError)
      return ExitCode.error
    }
    printOut("Launched KeyboardLocker to register its background agent.")

    for _ in 0 ..< agentPoll.attempts {
      try? await Task.sleep(for: agentPoll.interval)
      if (try? await client.status()) != nil {
        printOut("The KeyboardLocker agent is registered and reachable.")
        return ExitCode.success
      }
    }

    reportError("The KeyboardLocker agent is not reachable yet.", printError: printError)
    printError(
      "  If KeyboardLocker appears in System Settings → General → Login Items, enable it, " +
        "then retry. Locking also requires Accessibility access for the agent."
    )
    return ExitCode.error
  }

  /// Requests the system Accessibility prompt through the Agent, then polls briefly for the
  /// authoritative state: the prompt is asynchronous, so a sent request proves nothing about
  /// the grant. Exit 0 only when the Agent reports permission within the poll window.
  private static func executeRequestAccess(
    client: any KlockClientServing,
    accessPoll: (attempts: Int, interval: Duration),
    printOut: (String) -> Void,
    printError: (String) -> Void
  ) async -> Int32 {
    do {
      if try await client.hasAccessibilityPermission() {
        printOut("Accessibility access is already granted.")
        return ExitCode.success
      }

      try await client.requestAccessibilityPermission()
      printOut(
        "Requested the system Accessibility prompt for the KeyboardLocker agent; " +
          "waiting for the grant…"
      )

      for _ in 0 ..< accessPoll.attempts {
        try? await Task.sleep(for: accessPoll.interval)
        if try await client.hasAccessibilityPermission() {
          printOut("Accessibility access granted.")
          return ExitCode.success
        }
      }
    } catch {
      reportFailure(error, printError: printError)
      return ExitCode.error
    }

    printOut(
      "Accessibility access is not granted yet. " +
        "Enable KeyboardLocker in System Settings → Privacy & Security → Accessibility, " +
        "then re-run `klock request-access`."
    )
    return ExitCode.error
  }

  private static func executeStatus(
    output: KlockStatusOutput,
    client: any KlockClientServing,
    printOut: (String) -> Void,
    printError: (String) -> Void
  ) async -> Int32 {
    do {
      switch output {
      case .humanReadable, .json:
        printOut(output.render(isLocked: try await client.status()))
      case .snapshot:
        printOut(KlockStatusOutput.render(snapshot: try await client.lockStatusSnapshot()))
      }
      return ExitCode.success
    } catch {
      reportFailure(error, printError: printError)
      return ExitCode.error
    }
  }

  // MARK: - Helpers

  private static func reportFailure(_ error: Error, printError: (String) -> Void) {
    reportError(error.localizedDescription, printError: printError)
    if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
      printError("  \(suggestion)")
    }
    // The shared recovery text names the GUI registration path; point CLI users at the
    // native equivalent so the hint stays actionable from Terminal.
    if let clientError = error as? XPCClientError, case .serviceUnavailable = clientError {
      printError("  Or run `klock register-agent` to register it from Terminal.")
    }
  }

  private static func reportError(_ message: String, printError: (String) -> Void) {
    printError("Error: \(message)")
  }

  private static func reportWarning(_ message: String, printError: (String) -> Void) {
    printError("Warning: \(message)")
  }

  private static func printVersion(
    printOut: (String) -> Void,
    printError: (String) -> Void
  ) -> Int32 {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    guard let version, !version.isEmpty, let build, !build.isEmpty else {
      reportError("Version metadata is unavailable in this build.", printError: printError)
      return ExitCode.error
    }

    printOut("klock \(version) (\(build))")
    return ExitCode.success
  }

  private static func printUsage(to printOut: (String) -> Void) {
    printOut(
      """
      OVERVIEW: Control KeyboardLocker from Terminal.

      USAGE: klock <command> [options]

      COMMANDS:
        lock [--no-wait]    Lock the keyboard; by default, wait until it is unlocked.
        unlock              Unlock the keyboard.
        toggle              Toggle the lock state and print the new state.
        status [--json]     Print the current lock state.
        register-agent      Launch KeyboardLocker once to register its background agent.
        request-access      Request Accessibility access for the agent.
        help                Show this help message.
        version             Show the klock version.

      OPTIONS:
        --no-wait          Return after lock is confirmed; do not enable Ctrl+C unlock.
        --json             Emit a stable JSON object for status automation.
        --snapshot         Emit the full lock snapshot as JSON.
        -h, --help         Show this help message.
        -v, --version      Show the klock version.
      """
    )
  }

  private enum ExitCode {
    static let success: Int32 = 0
    static let error: Int32 = 1
  }
}
