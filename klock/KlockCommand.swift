import Foundation

/// One parsed `klock` invocation. A `nil` parse result means no arguments were given at all.
enum KlockCommand: Equatable {
  case help
  case version
  /// `autoUnlockSeconds` is the one-off `--for` override; it never touches the saved settings.
  case lock(wait: Bool, autoUnlockSeconds: TimeInterval?)
  case unlock
  case toggle
  case registerAgent
  case requestAccess
  case status(output: KlockStatusOutput)
}

enum KlockCommandLineError: Error, Equatable {
  case unknownCommand(String)
  case unexpectedArguments([String])
  case invalidDuration(String)
  case missingDurationValue
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
      return try parseLock(Array(arguments.dropFirst()))

    case "unlock":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .unlock

    case "toggle":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .toggle

    case "register-agent":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .registerAgent

    case "request-access":
      try rejectUnexpectedArguments(Array(arguments.dropFirst()))
      return .requestAccess

    case "status":
      switch Array(arguments.dropFirst()) {
      case []:
        return .status(output: .humanReadable)

      case ["--json"]:
        return .status(output: .json)

      case ["--snapshot"]:
        return .status(output: .snapshot)

      case let unexpectedArguments:
        throw KlockCommandLineError.unexpectedArguments(unexpectedArguments)
      }

    default:
      throw KlockCommandLineError.unknownCommand(command)
    }
  }

  /// `lock [--for DURATION] [--no-wait]` — flags may arrive in any order but never repeat.
  private static func parseLock(_ arguments: [String]) throws -> KlockCommand {
    var wait = true
    var autoUnlockSeconds: TimeInterval?
    var seenNoWait = false

    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--no-wait":
        guard !seenNoWait else {
          throw KlockCommandLineError.unexpectedArguments([argument])
        }
        seenNoWait = true
        wait = false

      case "--for":
        guard autoUnlockSeconds == nil else {
          throw KlockCommandLineError.unexpectedArguments([argument])
        }
        index += 1
        guard index < arguments.count else {
          throw KlockCommandLineError.missingDurationValue
        }
        autoUnlockSeconds = try parseDuration(arguments[index])

      default:
        throw KlockCommandLineError.unexpectedArguments([argument])
      }
      index += 1
    }

    return .lock(wait: wait, autoUnlockSeconds: autoUnlockSeconds)
  }

  /// Accepts a positive finite number of seconds, with an optional `s`/`m` suffix. The
  /// auto-unlock range itself stays the Agent's guardrail (`validated()`), not the parser's.
  private static func parseDuration(_ raw: String) throws -> TimeInterval {
    var numberPart = raw
    var multiplier: TimeInterval = 1
    if raw.hasSuffix("s") {
      numberPart = String(raw.dropLast())
    } else if raw.hasSuffix("m") {
      numberPart = String(raw.dropLast())
      multiplier = 60
    }

    guard let value = Double(numberPart), value.isFinite, value > 0 else {
      throw KlockCommandLineError.invalidDuration(raw)
    }
    return value * multiplier
  }

  private static func rejectUnexpectedArguments(_ arguments: [String]) throws {
    guard arguments.isEmpty else {
      throw KlockCommandLineError.unexpectedArguments(arguments)
    }
  }
}
