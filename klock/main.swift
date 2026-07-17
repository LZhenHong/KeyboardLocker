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
    case "help", "--help", "-h":
      guard arguments.count == 1 else {
        reportUnexpectedArguments(Array(arguments.dropFirst()))
      }
      printUsage()
      exit(ExitCode.success)

    case "version", "--version", "-v":
      guard arguments.count == 1 else {
        reportUnexpectedArguments(Array(arguments.dropFirst()))
      }
      printVersion()
      exit(ExitCode.success)

    case "lock":
      guard arguments.count == 1 else {
        reportUnexpectedArguments(Array(arguments.dropFirst()))
      }
      await executeLock()

    case "unlock":
      guard arguments.count == 1 else {
        reportUnexpectedArguments(Array(arguments.dropFirst()))
      }
      await executeUnlock()

    case "status":
      guard arguments.count == 1 else {
        reportUnexpectedArguments(Array(arguments.dropFirst()))
      }
      await executeStatus()

    default:
      printError("Unknown command: \(command)")
      printUsage()
      exit(ExitCode.error)
    }
  }

  // MARK: - Commands

  private static func executeLock() async {
    do {
      try await XPCClient.shared.lock()
    } catch {
      reportFailure(error)
      exit(ExitCode.error)
    }

    do {
      let hotkey = try await XPCClient.shared.currentSettings().unlockHotkey.displayString
      print("Locked. Press \(hotkey) to unlock.")
    } catch {
      print("Locked. Run `klock unlock` to unlock.")
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

  private static func executeStatus() async {
    do {
      let isLocked = try await XPCClient.shared.status()
      print(isLocked ? "Locked" : "Unlocked")
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

      USAGE: klock <command>

      COMMANDS:
        lock      Lock the keyboard and wait until it is unlocked.
        unlock    Unlock the keyboard.
        status    Print the current lock state.
        help      Show this help message.
        version   Show the klock version.

      OPTIONS:
        -h, --help       Show this help message.
        -v, --version    Show the klock version.
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
