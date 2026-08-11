import Client
import CoreGraphics
import Foundation
import XCTest

final class KlockCommandLineTests: XCTestCase {
  // MARK: - Parser

  func testParseReturnsNilWhenNoArgumentsGiven() throws {
    XCTAssertNil(try KlockCommandLineParser.parse([]))
  }

  func testParseAcceptsEveryValidCommandSpelling() throws {
    let cases: [(arguments: [String], expected: KlockCommand)] = [
      (["--help"], .help),
      (["-h"], .help),
      (["help"], .help),
      (["--version"], .version),
      (["-v"], .version),
      (["version"], .version),
      (["lock"], .lock(wait: true)),
      (["lock", "--no-wait"], .lock(wait: false)),
      (["unlock"], .unlock),
      (["status"], .status(output: .humanReadable)),
      (["status", "--json"], .status(output: .json)),
    ]

    for (arguments, expected) in cases {
      XCTAssertEqual(
        try KlockCommandLineParser.parse(arguments),
        expected,
        "arguments: \(arguments)"
      )
    }
  }

  func testParseRejectsUnknownCommands() {
    let cases = [["bogus"], ["--unknown-flag"]]

    for arguments in cases {
      XCTAssertThrowsError(
        try KlockCommandLineParser.parse(arguments),
        "arguments: \(arguments)"
      ) { error in
        XCTAssertEqual(
          error as? KlockCommandLineError,
          .unknownCommand(arguments[0]),
          "arguments: \(arguments)"
        )
      }
    }
  }

  func testParseRejectsUnexpectedArguments() {
    let cases: [(arguments: [String], expected: KlockCommandLineError)] = [
      (["lock", "extra"], .unexpectedArguments(["extra"])),
      (["lock", "--no-wait", "extra"], .unexpectedArguments(["--no-wait", "extra"])),
      (["status", "--xml"], .unexpectedArguments(["--xml"])),
      (["unlock", "now"], .unexpectedArguments(["now"])),
      (["--help", "extra"], .unexpectedArguments(["extra"])),
      (["version", "extra"], .unexpectedArguments(["extra"])),
    ]

    for (arguments, expected) in cases {
      XCTAssertThrowsError(
        try KlockCommandLineParser.parse(arguments),
        "arguments: \(arguments)"
      ) { error in
        XCTAssertEqual(error as? KlockCommandLineError, expected, "arguments: \(arguments)")
      }
    }
  }

  // MARK: - Command Execution

  func testInteractiveLockReportsAlreadyLockedWithoutWaiting() async {
    let client = FakeKlockClient()
    client.lockInteractivelyResult = .success(.alreadyLocked)

    let result = await runKlock(arguments: ["lock"], client: client)

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, ["Already locked. This command did not create a new lock."])
    XCTAssertEqual(result.stderr, [])
    XCTAssertEqual(client.lockInteractivelyCalls, 1)
    XCTAssertEqual(client.waitUntilUnlockedCalls, 0)
  }

  func testInteractiveLockPrintsHotkeyWaitsAndConfirmsUnlock() async {
    let client = FakeKlockClient()
    let hotkey = KeyboardLockerSettings.testFixture.unlockHotkey.displayString

    let result = await runKlock(arguments: ["lock"], client: client)

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(
      result.stdout,
      [
        "Locked. Press \(hotkey) or Ctrl+C to unlock.",
        "Unlocked.",
      ]
    )
    XCTAssertEqual(result.stderr, [])
    XCTAssertEqual(client.currentSettingsCalls, 1)
    XCTAssertEqual(client.waitUntilUnlockedCalls, 1)
  }

  func testInteractiveLockFallsBackToManualHintWhenSettingsUnavailable() async {
    let client = FakeKlockClient()
    client.settingsResult = .failure(Self.makeError("settings unavailable"))

    let result = await runKlock(arguments: ["lock"], client: client)

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(
      result.stdout,
      [
        "Locked. Press Ctrl+C to unlock, or run `klock unlock` from another Terminal.",
        "Unlocked.",
      ]
    )
    XCTAssertEqual(
      result.stderr,
      ["Warning: Could not read the configured unlock shortcut: settings unavailable"]
    )
  }

  func testInteractiveLockFailureReportsErrorOnStandardError() async throws {
    let client = FakeKlockClient()
    let error = XPCClientError.serviceUnavailable
    client.lockInteractivelyResult = .failure(error)

    let result = await runKlock(arguments: ["lock"], client: client)

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(result.stdout, [])
    XCTAssertEqual(
      result.stderr,
      [
        "Error: \(error.localizedDescription)",
        "  \(try XCTUnwrap(error.recoverySuggestion))",
      ]
    )
    XCTAssertEqual(client.waitUntilUnlockedCalls, 0)
  }

  func testNonInteractiveLockPrintsLockedWithoutWaiting() async {
    let client = FakeKlockClient()

    let result = await runKlock(arguments: ["lock", "--no-wait"], client: client)

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, ["Locked."])
    XCTAssertEqual(result.stderr, [])
    XCTAssertEqual(client.lockCalls, 1)
    XCTAssertEqual(client.lockInteractivelyCalls, 0)
    XCTAssertEqual(client.waitUntilUnlockedCalls, 0)
  }

  func testNonInteractiveLockFailureExitsWithError() async {
    let client = FakeKlockClient()
    client.lockResult = .failure(Self.makeError("lock failed"))

    let result = await runKlock(arguments: ["lock", "--no-wait"], client: client)

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(result.stdout, [])
    XCTAssertEqual(result.stderr, ["Error: lock failed"])
  }

  func testUnlockPrintsUnlockedOnSuccess() async {
    let client = FakeKlockClient()

    let result = await runKlock(arguments: ["unlock"], client: client)

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, ["Unlocked."])
    XCTAssertEqual(result.stderr, [])
    XCTAssertEqual(client.unlockCalls, 1)
  }

  func testUnlockFailureReportsErrorOnStandardError() async {
    let client = FakeKlockClient()
    client.unlockResult = .failure(Self.makeError("unlock failed"))

    let result = await runKlock(arguments: ["unlock"], client: client)

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(result.stdout, [])
    XCTAssertEqual(result.stderr, ["Error: unlock failed"])
  }

  func testStatusPrintsHumanReadableState() async {
    let client = FakeKlockClient()

    client.statusResult = .success(true)
    var result = await runKlock(arguments: ["status"], client: client)
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, ["Locked"])

    client.statusResult = .success(false)
    result = await runKlock(arguments: ["status"], client: client)
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, ["Unlocked"])

    XCTAssertEqual(result.stderr, [])
    XCTAssertEqual(client.statusCalls, 2)
  }

  func testStatusPrintsJSONState() async {
    let client = FakeKlockClient()

    client.statusResult = .success(true)
    var result = await runKlock(arguments: ["status", "--json"], client: client)
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, [#"{"locked":true}"#])

    client.statusResult = .success(false)
    result = await runKlock(arguments: ["status", "--json"], client: client)
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, [#"{"locked":false}"#])
  }

  func testInteractiveLockExitsWithErrorWhenWaitingForUnlockFails() async throws {
    let client = FakeKlockClient()
    let error = XPCClientError.serviceUnavailable
    client.waitUntilUnlockedResult = .failure(error)
    let hotkey = KeyboardLockerSettings.testFixture.unlockHotkey.displayString

    let result = await runKlock(arguments: ["lock"], client: client)

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(result.stdout, ["Locked. Press \(hotkey) or Ctrl+C to unlock."])
    XCTAssertEqual(
      result.stderr,
      [
        "Error: \(error.localizedDescription)",
        "  \(try XCTUnwrap(error.recoverySuggestion))",
      ]
    )
  }

  // MARK: - Helpers

  private static func makeError(_ message: String) -> NSError {
    NSError(
      domain: "KlockCommandLineTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  private func runKlock(
    arguments: [String],
    client: FakeKlockClient
  ) async -> (exitCode: Int32, stdout: [String], stderr: [String]) {
    var stdout: [String] = []
    var stderr: [String] = []
    let exitCode = await KlockCLI.run(
      arguments: arguments,
      client: client,
      printOut: { stdout.append($0) },
      printError: { stderr.append($0) }
    )
    return (exitCode, stdout, stderr)
  }
}

private extension KeyboardLockerSettings {
  static let testFixture = KeyboardLockerSettings(
    autoUnlockPolicy: .disabled,
    unlockHotkey: Hotkey(keyCode: 37, modifierFlags: [.maskCommand, .maskControl])
  )
}

private final class FakeKlockClient: KlockClientServing, @unchecked Sendable {
  var settingsResult: Result<KeyboardLockerSettings, Error> = .success(.testFixture)
  var lockInteractivelyResult: Result<LockRequestOutcome, Error> = .success(.acquired)
  var lockResult: Result<Void, Error> = .success(())
  var unlockResult: Result<Void, Error> = .success(())
  var statusResult: Result<Bool, Error> = .success(false)
  var waitUntilUnlockedResult: Result<Void, Error> = .success(())

  private(set) var currentSettingsCalls = 0
  private(set) var lockInteractivelyCalls = 0
  private(set) var lockCalls = 0
  private(set) var unlockCalls = 0
  private(set) var statusCalls = 0
  private(set) var waitUntilUnlockedCalls = 0

  func currentSettings() async throws -> KeyboardLockerSettings {
    currentSettingsCalls += 1
    return try settingsResult.get()
  }

  func lockInteractively() async throws -> LockRequestOutcome {
    lockInteractivelyCalls += 1
    return try lockInteractivelyResult.get()
  }

  func lock() async throws {
    lockCalls += 1
    try lockResult.get()
  }

  func unlock() async throws {
    unlockCalls += 1
    try unlockResult.get()
  }

  func status() async throws -> Bool {
    statusCalls += 1
    return try statusResult.get()
  }

  func waitUntilUnlocked() async throws {
    waitUntilUnlockedCalls += 1
    try waitUntilUnlockedResult.get()
  }
}
