//
//  main.swift
//  KeyboardLockerTool
//
//  Created by Eden on 2025/7/25.
//

import Core
import Foundation

/// CLI entry point for interacting with KeyboardLocker core features.
/// Maps command-line arguments to the same behaviors exposed via the GUI app.
enum KeyboardLockerCLI {
  static func run() -> Int32 {
    do {
      let command = try CLICommand.parse(from: CommandLine.arguments)
      let dependencies = CLIDependencies()
      let runner = CLICommandRunner(dependencies: dependencies)
      try runner.run(command)
      return EXIT_SUCCESS
    } catch CLIError.helpRequested {
      print(CLICommand.helpText)
      return EXIT_SUCCESS
    } catch let error as CLIError {
      print("❌ \(error.localizedDescription)")
      return EXIT_FAILURE
    } catch {
      print("❌ Unexpected error: \(error.localizedDescription)")
      return EXIT_FAILURE
    }
  }
}

// MARK: - Command Parsing

enum CLICommand: Equatable {
  case lock
  case unlock
  case toggle

  static func parse(from arguments: [String]) throws -> CLICommand {
    guard arguments.count > 1 else {
      throw CLIError.helpRequested
    }

    var args = Array(arguments.dropFirst())
    let command = args.removeFirst()

    switch command.lowercased() {
    case "lock":
      return .lock

    case "unlock":
      return .unlock

    case "toggle":
      return .toggle

    case "-h", "--help":
      throw CLIError.helpRequested

    default:
      throw CLIError.unknownCommand(command)
    }
  }

  static var helpText: String {
    """
    KeyboardLocker CLI

    Usage:
     KeyboardLockerTool <command>

    Commands:
    	lock               Lock the keyboard immediately
    	unlock             Unlock the keyboard
    	toggle             Toggle lock state

    Global Options:
    	-h, --help         Show this help text

    Examples:
      KeyboardLockerTool lock
    """
  }
}

enum CLIError: LocalizedError {
  case helpRequested
  case unknownCommand(String)
  case invalidArguments(String)
  case operationFailed(String)

  var errorDescription: String? {
    switch self {
    case .helpRequested:
      nil
    case let .unknownCommand(command):
      "Unknown command: \(command). Use --help for available commands."
    case let .invalidArguments(details):
      "Invalid arguments: \(details)"
    case let .operationFailed(message):
      message
    }
  }
}

// MARK: - Dependencies

/// Minimal dependency container reused from the app
struct CLIDependencies {
  let core: KeyboardLockCore
  let config: CoreConfiguration

  init(core: KeyboardLockCore = .shared, config: CoreConfiguration = .shared) {
    self.core = core
    self.config = config
  }
}

// MARK: - Command Runner

final class CLICommandRunner {
  private let core: KeyboardLockCore
  private let config: CoreConfiguration

  init(dependencies: CLIDependencies) {
    core = dependencies.core
    config = dependencies.config

    core.onUnlockHotkeyDetected = { [weak self] in
      self?.handleUnlockHotkey()
    }
  }

  func run(_ command: CLICommand) throws {
    switch command {
    case .lock:
      try lock()
    case .unlock:
      unlock()
    case .toggle:
      try toggle()
    }
  }

  private func lock() throws {
    do {
      try core.lockKeyboard()
      print("🔒 Keyboard locked. Press \(config.hotkey.displayString) to unlock.")
      waitUntilUnlocked()
      print("🔓 Keyboard unlocked")
    } catch {
      throw CLIError.operationFailed(error.localizedDescription)
    }
  }

  private func unlock() {
    guard core.isLocked else {
      print("ℹ️ Keyboard already unlocked")
      return
    }

    core.unlockKeyboard()
    print("🔓 Keyboard unlocked")
  }

  private func toggle() throws {
    if core.isLocked {
      unlock()
    } else {
      try lock()
    }
  }

  private func waitUntilUnlocked() {
    while core.isLocked {
      CFRunLoopRunInMode(.defaultMode, 0.25, true)
    }
  }

  private func handleUnlockHotkey() {
    print("🔑 Hotkey detected, unlocking…")
    core.unlockKeyboard()
  }
}

let exitCode = KeyboardLockerCLI.run()
exit(exitCode)
