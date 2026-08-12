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
      (["register-agent"], .registerAgent),
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
      (["register-agent", "now"], .unexpectedArguments(["now"])),
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

  // MARK: - Register Agent

  func testRegisterAgentReportsAlreadyReachableWithoutOpeningApp() async {
    let client = FakeKlockClient()
    var openCalls = 0

    let result = await runKlock(
      arguments: ["register-agent"],
      client: client,
      openKeyboardLockerApp: { openCalls += 1 }
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, ["The KeyboardLocker agent is already registered and reachable."])
    XCTAssertEqual(result.stderr, [])
    XCTAssertEqual(openCalls, 0)
    XCTAssertEqual(client.statusCalls, 1)
  }

  func testRegisterAgentOpensAppAndConfirmsWhenAgentBecomesReachable() async {
    let client = FakeKlockClient()
    client.statusResults = [
      .failure(Self.makeError("unreachable")),
      .success(false),
    ]
    var openCalls = 0

    let result = await runKlock(
      arguments: ["register-agent"],
      client: client,
      openKeyboardLockerApp: { openCalls += 1 },
      agentPoll: (attempts: 3, interval: .zero)
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(
      result.stdout,
      [
        "Launched KeyboardLocker to register its background agent.",
        "The background agent is registered and reachable.",
      ]
    )
    XCTAssertEqual(result.stderr, [])
    XCTAssertEqual(openCalls, 1)
    XCTAssertEqual(client.statusCalls, 2)
  }

  func testRegisterAgentFailsWhenAgentStaysUnreachable() async {
    let client = FakeKlockClient()
    client.statusResult = .failure(Self.makeError("unreachable"))
    var openCalls = 0

    let result = await runKlock(
      arguments: ["register-agent"],
      client: client,
      openKeyboardLockerApp: { openCalls += 1 },
      agentPoll: (attempts: 2, interval: .zero)
    )

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(result.stdout, ["Launched KeyboardLocker to register its background agent."])
    XCTAssertEqual(result.stderr.first, "Error: The background agent is not reachable yet.")
    XCTAssertEqual(openCalls, 1)
    XCTAssertEqual(client.statusCalls, 3)
  }

  func testRegisterAgentReportsOpenFailure() async {
    let client = FakeKlockClient()
    client.statusResult = .failure(Self.makeError("unreachable"))
    let error = KlockAppOpener.OpenerError.appNotFound

    let result = await runKlock(
      arguments: ["register-agent"],
      client: client,
      openKeyboardLockerApp: { throw error }
    )

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(result.stdout, [])
    XCTAssertEqual(
      result.stderr,
      [
        "Error: \(error.localizedDescription)",
        "  \(try XCTUnwrap(error.recoverySuggestion))",
      ]
    )
  }

  // MARK: - Termination Guard

  func testInteractiveLockInstallsAndCancelsTerminationGuardWhileWaiting() async {
    let client = FakeKlockClient()
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(terminationGuard.installCalls, 1)
    XCTAssertEqual(terminationGuard.cancelCalls, 1)
  }

  func testInteractiveLockAlreadyLockedSkipsTerminationGuard() async {
    let client = FakeKlockClient()
    client.lockInteractivelyResult = .success(.alreadyLocked)
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(terminationGuard.installCalls, 0)
  }

  func testInteractiveLockFailureSkipsTerminationGuard() async {
    let client = FakeKlockClient()
    client.lockInteractivelyResult = .failure(Self.makeError("lock failed"))
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(terminationGuard.installCalls, 0)
  }

  func testInteractiveLockWaitFailureCancelsTerminationGuard() async {
    let client = FakeKlockClient()
    client.waitUntilUnlockedResult = .failure(Self.makeError("wait failed"))
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(terminationGuard.installCalls, 1)
    XCTAssertEqual(terminationGuard.cancelCalls, 1)
  }

  func testNonInteractiveLockSkipsTerminationGuard() async {
    let client = FakeKlockClient()
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock", "--no-wait"],
      client: client,
      terminationGuard: terminationGuard
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(terminationGuard.installCalls, 0)
  }

  func testUnlockBeforeTerminationReleasesCreatedLock() async {
    let client = FakeKlockClient()
    var stderr: [String] = []

    await KlockCLI.unlockBeforeTermination(client: client, printError: { stderr.append($0) })

    XCTAssertEqual(client.unlockCalls, 1)
    XCTAssertEqual(stderr, ["Terminated; released the keyboard lock created by this command."])
  }

  func testUnlockBeforeTerminationReportsFailureWithRecoveryHint() async {
    let client = FakeKlockClient()
    client.unlockResult = .failure(Self.makeError("agent gone"))
    var stderr: [String] = []

    await KlockCLI.unlockBeforeTermination(client: client, printError: { stderr.append($0) })

    XCTAssertEqual(client.unlockCalls, 1)
    XCTAssertEqual(stderr.count, 1)
    XCTAssertTrue(stderr[0].contains("could not release"), "stderr: \(stderr)")
    XCTAssertTrue(stderr[0].contains("agent gone"), "stderr: \(stderr)")
    XCTAssertTrue(stderr[0].contains("Unlock Now"), "stderr: \(stderr)")
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
    client: FakeKlockClient,
    openKeyboardLockerApp: @escaping () throws -> Void = {},
    agentPoll: (attempts: Int, interval: Duration) = (attempts: 1, interval: .zero),
    terminationGuard: any KlockTerminationGuarding = NullKlockTerminationGuard()
  ) async -> (exitCode: Int32, stdout: [String], stderr: [String]) {
    var stdout: [String] = []
    var stderr: [String] = []
    let exitCode = await KlockCLI.run(
      arguments: arguments,
      client: client,
      openKeyboardLockerApp: openKeyboardLockerApp,
      agentPoll: agentPoll,
      terminationGuard: terminationGuard,
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
  /// When set, each `status()` call consumes the next queued result before falling back to
  /// `statusResult`, so tests can script an Agent that becomes reachable after registration.
  var statusResults: [Result<Bool, Error>]?
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
    if statusResults?.isEmpty == false {
      return try statusResults!.removeFirst().get()
    }
    return try statusResult.get()
  }

  func waitUntilUnlocked() async throws {
    waitUntilUnlockedCalls += 1
    try waitUntilUnlockedResult.get()
  }
}

private final class FakeKlockTerminationGuard: KlockTerminationGuarding, @unchecked Sendable {
  private(set) var installCalls = 0
  private(set) var cancelCalls = 0

  func install(onTermination _: @escaping (Int32) -> Void) -> () -> Void {
    installCalls += 1
    return { [self] in
      cancelCalls += 1
    }
  }
}

/// Default guard for tests that do not exercise the termination path: never touches process
/// signal state, so the XCTest process keeps its default signal dispositions.
private struct NullKlockTerminationGuard: KlockTerminationGuarding {
  func install(onTermination _: @escaping (Int32) -> Void) -> () -> Void {
    {}
  }
}
