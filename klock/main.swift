//
//  main.swift
//  klock
//
//  Created by Eden on 2025/11/19.
//

import Client
import Foundation

await KlockCLI.run()

// MARK: - CLI

enum KlockCLI {
  static func run() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
      printUsage()
      exit(ExitCode.success)
    }

    switch command {
    case "--help", "-h", "help":
      guard arguments.count == 1 else {
        reportUnexpectedArguments(Array(arguments.dropFirst()))
      }
      printUsage()
      exit(ExitCode.success)

    case "--version", "-v", "version":
      guard arguments.count == 1 else {
        reportUnexpectedArguments(Array(arguments.dropFirst()))
      }
      printVersion()
      exit(ExitCode.success)

    case "lock":
      switch Array(arguments.dropFirst()) {
      case []:
        await executeInteractiveLock()

      case ["--no-wait"]:
        await executeNonInteractiveLock()

      case let unexpectedArguments:
        reportUnexpectedArguments(unexpectedArguments)
      }

    case "unlock":
      guard arguments.count == 1 else {
        reportUnexpectedArguments(Array(arguments.dropFirst()))
      }
      await executeUnlock()

    case "status":
      switch Array(arguments.dropFirst()) {
      case []:
        await executeStatus(output: .humanReadable)

      case ["--json"]:
        await executeStatus(output: .json)

      case let unexpectedArguments:
        reportUnexpectedArguments(unexpectedArguments)
      }

    default:
      printError("Unknown command: \(command)")
      printUsage()
      exit(ExitCode.error)
    }
  }

  // MARK: - Commands

  private static func executeInteractiveLock() async {
    let unlockHotkey: Result<String, Error>
    do {
      unlockHotkey = try await .success(
        XPCClient.shared.currentSettings().unlockHotkey.displayString
      )
    } catch {
      unlockHotkey = .failure(error)
    }

    let outcome: LockRequestOutcome
    do {
      outcome = try await XPCClient.shared.lockInteractively()
    } catch {
      reportFailure(error)
      exit(ExitCode.error)
    }

    guard outcome == .acquired else {
      print("Already locked. This command did not create a new lock.")
      exit(ExitCode.success)
    }

    switch unlockHotkey {
    case let .success(hotkey):
      print("Locked. Press \(hotkey) or Ctrl+C to unlock.")

    case let .failure(error):
      print("Locked. Press Ctrl+C to unlock, or run `klock unlock` from another Terminal.")
      printWarning("Could not read the configured unlock shortcut: \(error.localizedDescription)")
    }

    do {
      try await XPCClient.shared.waitUntilUnlocked()
      print("Unlocked.")
      exit(ExitCode.success)
    } catch {
      reportFailure(error)
      exit(ExitCode.error)
    }
  }

  private static func executeNonInteractiveLock() async {
    do {
      try await XPCClient.shared.lock()
      print("Locked.")
      exit(ExitCode.success)
    } catch {
      reportFailure(error)
      exit(ExitCode.error)
    }
  }

  private static func executeUnlock() async {
    do {
      try await XPCClient.shared.unlock()
      print("Unlocked.")
      exit(ExitCode.success)
    } catch {
      reportFailure(error)
      exit(ExitCode.error)
    }
  }

  private static func executeStatus(output: KlockStatusOutput) async {
    do {
      let isLocked = try await XPCClient.shared.status()
      print(output.render(isLocked: isLocked))
      exit(ExitCode.success)
    } catch {
      reportFailure(error)
      exit(ExitCode.error)
    }
  }

  // MARK: - Helpers

  private static func reportFailure(_ error: Error) {
    printError(error.localizedDescription)
    if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
      printStandardError("  \(suggestion)")
    }
  }

  private static func reportUnexpectedArguments(_ arguments: [String]) -> Never {
    printError("Unexpected argument\(arguments.count == 1 ? "" : "s"): \(arguments.joined(separator: " "))")
    printUsage()
    exit(ExitCode.error)
  }

  private static func printVersion() {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    guard let version, !version.isEmpty, let build, !build.isEmpty else {
      printError("Version metadata is unavailable in this build.")
      exit(ExitCode.error)
    }

    print("klock \(version) (\(build))")
  }

  private static func printUsage() {
    print(
      """
      OVERVIEW: Control KeyboardLocker from Terminal.

      USAGE: klock <command> [options]

      COMMANDS:
        lock [--no-wait]    Lock the keyboard; by default, wait until it is unlocked.
        unlock              Unlock the keyboard.
        status [--json]     Print the current lock state.
        help                Show this help message.
        version             Show the klock version.

      OPTIONS:
        --no-wait          Return after lock is confirmed; do not enable Ctrl+C unlock.
        --json             Emit a stable JSON object for status automation.
        -h, --help         Show this help message.
        -v, --version      Show the klock version.
      """
    )
  }

  private static func printError(_ message: String) {
    printStandardError("Error: \(message)")
  }

  private static func printWarning(_ message: String) {
    printStandardError("Warning: \(message)")
  }

  private static func printStandardError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }

  private enum ExitCode {
    static let success: Int32 = 0
    static let error: Int32 = 1
  }
}
