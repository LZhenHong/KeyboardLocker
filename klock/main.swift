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
    guard let command = CommandLine.arguments.dropFirst().first else {
      printUsage()
      exit(ExitCode.error)
    }

    switch command {
    case "lock":
      await executeLock()
    case "unlock":
      await executeUnlock()
    case "status":
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
      print("  \(suggestion)")
    }
  }

  private static func printUsage() {
    print("Usage: klock <lock|unlock|status>")
  }

  private static func printError(_ message: String) {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
  }

  private static func printWarning(_ message: String) {
    FileHandle.standardError.write(Data("Warning: \(message)\n".utf8))
  }

  private enum ExitCode {
    static let success: Int32 = 0
    static let error: Int32 = 1
  }
}
