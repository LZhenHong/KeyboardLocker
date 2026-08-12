import Foundation

/// One parsed `klock` invocation. A `nil` parse result means no arguments were given at all.
enum KlockCommand: Equatable {
  case help
  case version
  case lock(wait: Bool)
  case unlock
  case toggle
  case registerAgent
  case status(output: KlockStatusOutput)
}

enum KlockCommandLineError: Error, Equatable {
  case unknownCommand(String)
  case unexpectedArguments([String])
}

/// Pure argument parsing for `klock`, kept free of I/O and process exit so the accepted
/// command/flag matrix can be exhaustively unit-tested.
enum KlockCommandLineParser {
  static func parse(_ arguments: [String]) throws -> KlockCommand? {
    guard let command = arguments.first else {
      return nil
    }

    switch command {
    case "--help", "-h", "help":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .help

    case "--version", "-v", "version":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .version

    case "lock":
      switch Array(arguments.dropFirst()) {
      case []:
        return .lock(wait: true)

      case ["--no-wait"]:
        return .lock(wait: false)

      case let unexpectedArguments:
        throw KlockCommandLineError.unexpectedArguments(unexpectedArguments)
      }

    case "unlock":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .unlock

    case "toggle":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .toggle

    case "register-agent":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .registerAgent

    case "status":
      switch Array(arguments.dropFirst()) {
      case []:
        return .status(output: .humanReadable)

      case ["--json"]:
        return .status(output: .json)

      case let unexpectedArguments:
        throw KlockCommandLineError.unexpectedArguments(unexpectedArguments)
      }

    default:
      throw KlockCommandLineError.unknownCommand(command)
    }
  }

  private static func rejectUnexpectedArguments(_ arguments: [String]) throws {
    guard arguments.isEmpty else {
      throw KlockCommandLineError.unexpectedArguments(arguments)
    }
  }
}
