//
//  main.swift
//  klock
//
//  Created by Eden on 2025/11/19.
//

import Client
import Foundation

// MARK: - Entry Point

KlockCLI.run()

// MARK: - CLI

enum KlockCLI {
  private static var session: LockSessionController?
  private static var stateToken: ObserverToken?

  static func run() {
    guard let command = CommandLine.arguments.dropFirst().first else {
      printUsage()
      exit(ExitCode.error)
    }

    switch command {
    case "lock":
      executeLock()
    case "unlock":
      executeUnlock()
    case "status":
      executeStatus()
    default:
      printError("Unknown command: \(command)")
      printUsage()
      exit(ExitCode.error)
    }
  }

  // MARK: - Commands

  private static func executeLock() {
    print("Locking...")

    session = XPCClient.startLockSession()
    session?.lock { error in
      if let error {
        printError(error.localizedDescription)
        if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
          print("  \(suggestion)")
        }
        exit(ExitCode.error)
      }
      let hotkey = KeyboardLockerSettings.default.unlockHotkey.displayString
      print("Locked. Press \(hotkey) to unlock.")
    }

    // Listen for external unlock (hotkey pressed)
    stateToken = LockStateSubscriber.subscribe { isLocked in
      if !isLocked {
        print("Unlocked.")
        stateToken = nil
        session = nil
        exit(ExitCode.success)
      }
    }

    RunLoop.main.run()
  }

  private static func executeUnlock() {
    var exitCode = ExitCode.success
    let sem = DispatchSemaphore(value: 0)

    XPCClient.unlock { error in
      if let error {
        printError(error.localizedDescription)
        exitCode = ExitCode.error
      } else {
        print("Unlocked.")
      }
      sem.signal()
    }

    sem.wait()
    exit(exitCode)
  }

  private static func executeStatus() {
    var exitCode = ExitCode.success
    let sem = DispatchSemaphore(value: 0)

    XPCClient.status { isLocked, error in
      if let error {
        printError(error.localizedDescription)
        exitCode = ExitCode.error
      } else {
        print(isLocked ? "Locked" : "Unlocked")
      }
      sem.signal()
    }

    sem.wait()
    exit(exitCode)
  }

  // MARK: - Helpers

  private static func printUsage() {
    print("Usage: klock <lock|unlock|status>")
  }

  private static func printError(_ message: String) {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
  }

  private enum ExitCode {
    static let success: Int32 = 0
    static let error: Int32 = 1
  }
}
