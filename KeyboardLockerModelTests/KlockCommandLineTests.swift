import Client
import CoreGraphics
import Foundation
import Testing

@Suite(.serialized)
struct KlockCommandLineTests {
  // MARK: - Parser

  @Test
  func parseReturnsNilWhenNoArgumentsGiven() throws {
    #expect(try KlockCommandLineParser.parse([]) == nil)
  }

  @Test
  func parseAcceptsEveryValidCommandSpelling() throws {
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
      (["toggle"], .toggle),
      (["register-agent"], .registerAgent),
      (["request-access"], .requestAccess),
      (["status"], .status(output: .humanReadable)),
      (["status", "--json"], .status(output: .json)),
      (["status", "--snapshot"], .status(output: .snapshot)),
    ]

    for (arguments, expected) in cases {
      #expect(try KlockCommandLineParser.parse(arguments) == expected, "arguments: \(arguments)")
    }
  }

  @Test
  func parseRejectsUnknownCommands() {
    let cases = [["bogus"], ["--unknown-flag"]]

    for arguments in cases {
      let error = #expect(
        throws: KlockCommandLineError.self,
        "arguments: \(arguments)"
      ) {
        try KlockCommandLineParser.parse(arguments)
      }
      #expect(error == .unknownCommand(arguments[0]), "arguments: \(arguments)")
    }
  }

  @Test
  func parseRejectsUnexpectedArguments() {
    let cases: [(arguments: [String], expected: KlockCommandLineError)] = [
      (["lock", "extra"], .unexpectedArguments(["extra"])),
      (["lock", "--no-wait", "extra"], .unexpectedArguments(["--no-wait", "extra"])),
      (["status", "--xml"], .unexpectedArguments(["--xml"])),
      (["status", "--json", "--snapshot"], .unexpectedArguments(["--json", "--snapshot"])),
      (["unlock", "now"], .unexpectedArguments(["now"])),
      (["toggle", "now"], .unexpectedArguments(["now"])),
      (["register-agent", "now"], .unexpectedArguments(["now"])),
      (["request-access", "now"], .unexpectedArguments(["now"])),
      (["--help", "extra"], .unexpectedArguments(["extra"])),
      (["version", "extra"], .unexpectedArguments(["extra"])),
    ]

    for (arguments, expected) in cases {
      let error = #expect(
        throws: KlockCommandLineError.self,
        "arguments: \(arguments)"
      ) {
        try KlockCommandLineParser.parse(arguments)
      }
      #expect(error == expected, "arguments: \(arguments)")
    }
  }

  // MARK: - Command Execution

  @Test
  func interactiveLockReportsAlreadyLockedWithoutWaiting() async {
    let client = FakeKlockClient()
    client.lockInteractivelyResult = .success(.alreadyLocked)

    let result = await runKlock(arguments: ["lock"], client: client)

    #expect(result.exitCode == 0)
    #expect(result.stdout == ["Already locked. This command did not create a new lock."])
    #expect(result.stderr == [])
    #expect(client.lockInteractivelyCalls == 1)
    #expect(client.waitUntilUnlockedCalls == 0)
  }

  @Test
  func interactiveLockPrintsHotkeyWaitsAndConfirmsUnlock() async {
    let client = FakeKlockClient()
    let hotkey = KeyboardLockerSettings.testFixture.unlockHotkey.displayString

    let result = await runKlock(arguments: ["lock"], client: client)

    #expect(result.exitCode == 0)
    #expect(result.stdout == [
      "Locked. Press \(hotkey) or Ctrl+C to unlock.",
      "Unlocked.",
    ])
    #expect(result.stderr == [])
    #expect(client.currentSettingsCalls == 1)
    #expect(client.waitUntilUnlockedCalls == 1)
  }

  @Test
  func interactiveLockFallsBackToManualHintWhenSettingsUnavailable() async {
    let client = FakeKlockClient()
    client.settingsResult = .failure(Self.makeError("settings unavailable"))

    let result = await runKlock(arguments: ["lock"], client: client)

    #expect(result.exitCode == 0)
    #expect(result.stdout == [
      "Locked. Press Ctrl+C to unlock, or run `klock unlock` from another Terminal.",
      "Unlocked.",
    ])
    #expect(result.stderr == ["Warning: Could not read the configured unlock shortcut: settings unavailable"])
  }

  @Test
  func interactiveLockFailureReportsErrorOnStandardError() async throws {
    let client = FakeKlockClient()
    let error = XPCClientError.serviceUnavailable
    client.lockInteractivelyResult = .failure(error)

    let result = await runKlock(arguments: ["lock"], client: client)

    #expect(result.exitCode == 1)
    #expect(result.stdout == [])
    #expect(try result.stderr == [
      "Error: \(error.localizedDescription)",
      "  \(#require(error.recoverySuggestion))",
      "  Or run `klock register-agent` to register it from Terminal.",
    ])
    #expect(client.waitUntilUnlockedCalls == 0)
  }

  @Test
  func nonInteractiveLockPrintsLockedWithoutWaiting() async {
    let client = FakeKlockClient()

    let result = await runKlock(arguments: ["lock", "--no-wait"], client: client)

    #expect(result.exitCode == 0)
    #expect(result.stdout == ["Locked."])
    #expect(result.stderr == [])
    #expect(client.lockCalls == 1)
    #expect(client.lockInteractivelyCalls == 0)
    #expect(client.waitUntilUnlockedCalls == 0)
  }

  @Test
  func nonInteractiveLockFailureExitsWithError() async {
    let client = FakeKlockClient()
    client.lockResult = .failure(Self.makeError("lock failed"))

    let result = await runKlock(arguments: ["lock", "--no-wait"], client: client)

    #expect(result.exitCode == 1)
    #expect(result.stdout == [])
    #expect(result.stderr == ["Error: lock failed"])
  }

  @Test
  func unlockPrintsUnlockedOnSuccess() async {
    let client = FakeKlockClient()

    let result = await runKlock(arguments: ["unlock"], client: client)

    #expect(result.exitCode == 0)
    #expect(result.stdout == ["Unlocked."])
    #expect(result.stderr == [])
    #expect(client.unlockCalls == 1)
  }

  @Test
  func unlockFailureReportsErrorOnStandardError() async {
    let client = FakeKlockClient()
    client.unlockResult = .failure(Self.makeError("unlock failed"))

    let result = await runKlock(arguments: ["unlock"], client: client)

    #expect(result.exitCode == 1)
    #expect(result.stdout == [])
    #expect(result.stderr == ["Error: unlock failed"])
  }

  @Test
  func togglePrintsResultingStateAcrossRoundTrip() async {
    let client = FakeKlockClient()
    client.toggleResults = [.success(true), .success(false)]

    var result = await runKlock(arguments: ["toggle"], client: client)
    #expect(result.exitCode == 0)
    #expect(result.stdout == ["Locked."])

    result = await runKlock(arguments: ["toggle"], client: client)
    #expect(result.exitCode == 0)
    #expect(result.stdout == ["Unlocked."])

    #expect(result.stderr == [])
    #expect(client.toggleCalls == 2)
  }

  @Test
  func toggleFailureReportsErrorOnStandardError() async {
    let client = FakeKlockClient()
    client.toggleResult = .failure(Self.makeError("toggle failed"))

    let result = await runKlock(arguments: ["toggle"], client: client)

    #expect(result.exitCode == 1)
    #expect(result.stdout == [])
    #expect(result.stderr == ["Error: toggle failed"])
  }

  @Test
  func statusPrintsHumanReadableState() async {
    let client = FakeKlockClient()

    client.statusResult = .success(true)
    var result = await runKlock(arguments: ["status"], client: client)
    #expect(result.exitCode == 0)
    #expect(result.stdout == ["Locked"])

    client.statusResult = .success(false)
    result = await runKlock(arguments: ["status"], client: client)
    #expect(result.exitCode == 0)
    #expect(result.stdout == ["Unlocked"])

    #expect(result.stderr == [])
    #expect(client.statusCalls == 2)
  }

  @Test
  func statusPrintsJSONState() async {
    let client = FakeKlockClient()

    client.statusResult = .success(true)
    var result = await runKlock(arguments: ["status", "--json"], client: client)
    #expect(result.exitCode == 0)
    #expect(result.stdout == [#"{"locked":true}"#])

    client.statusResult = .success(false)
    result = await runKlock(arguments: ["status", "--json"], client: client)
    #expect(result.exitCode == 0)
    #expect(result.stdout == [#"{"locked":false}"#])
  }

  @Test
  func statusSnapshotPrintsSnapshotContract() async {
    let client = FakeKlockClient()
    client.lockStatusSnapshotResult = .success(
      LockStatusSnapshot(
        capturedAt: Date(timeIntervalSince1970: 1_700_000_030),
        isLocked: true,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        autoUnlockTargetDate: Date(timeIntervalSince1970: 1_700_000_060),
        settings: .testFixture
      )
    )

    let result = await runKlock(arguments: ["status", "--snapshot"], client: client)

    #expect(result.exitCode == 0)
    #expect(result.stdout == [
      """
      {"autoUnlockTargetDate":"2023-11-14T22:14:20Z","locked":true,"startedAt":"2023-11-14T22:13:20Z","unlockHotkey":"⌃⌘L"}
      """,
    ])
    #expect(result.stderr == [])
    #expect(client.lockStatusSnapshotCalls == 1)
    #expect(client.statusCalls == 0)
  }

  @Test
  func statusSnapshotFailureReportsErrorWithoutFallback() async {
    let client = FakeKlockClient()
    client.lockStatusSnapshotResult = .failure(Self.makeError("snapshot unsupported"))

    let result = await runKlock(arguments: ["status", "--snapshot"], client: client)

    #expect(result.exitCode == 1)
    #expect(result.stdout == [])
    #expect(result.stderr == ["Error: snapshot unsupported"])
    #expect(client.statusCalls == 0)
  }

  @Test
  func interactiveLockExitsWithErrorWhenWaitingForUnlockFails() async throws {
    let client = FakeKlockClient()
    let error = XPCClientError.serviceUnavailable
    client.waitUntilUnlockedResult = .failure(error)
    let hotkey = KeyboardLockerSettings.testFixture.unlockHotkey.displayString

    let result = await runKlock(arguments: ["lock"], client: client)

    #expect(result.exitCode == 1)
    #expect(result.stdout == ["Locked. Press \(hotkey) or Ctrl+C to unlock."])
    #expect(try result.stderr == [
      "Error: \(error.localizedDescription)",
      "  \(#require(error.recoverySuggestion))",
      "  Or run `klock register-agent` to register it from Terminal.",
    ])
  }

  // MARK: - Request Access

  @Test
  func requestAccessReportsAlreadyGrantedWithoutPrompting() async {
    let client = FakeKlockClient()
    client.hasAccessibilityPermissionResult = .success(true)

    let result = await runKlock(arguments: ["request-access"], client: client)

    #expect(result.exitCode == 0)
    #expect(result.stdout == ["Accessibility access is already granted."])
    #expect(result.stderr == [])
    #expect(client.requestAccessibilityPermissionCalls == 0)
  }

  @Test
  func requestAccessPromptsThenPollsUntilGranted() async {
    let client = FakeKlockClient()
    client.hasAccessibilityPermissionResults = [
      .success(false),
      .success(false),
      .success(true),
    ]

    let result = await runKlock(
      arguments: ["request-access"],
      client: client,
      accessPoll: (attempts: 5, interval: .zero)
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout == [
      "Requested the system Accessibility prompt for the KeyboardLocker agent; waiting for the grant…",
      "Accessibility access granted.",
    ])
    #expect(result.stderr == [])
    #expect(client.requestAccessibilityPermissionCalls == 1)
    #expect(client.hasAccessibilityPermissionCalls == 3)
  }

  @Test
  func requestAccessReportsPendingWhenWindowExpires() async {
    let client = FakeKlockClient()

    let result = await runKlock(
      arguments: ["request-access"],
      client: client,
      accessPoll: (attempts: 2, interval: .zero)
    )

    #expect(result.exitCode == 1)
    #expect(result.stdout.first == "Requested the system Accessibility prompt for the KeyboardLocker agent; waiting for the grant…")
    #expect(result.stdout.last == "Accessibility access is not granted yet. Enable KeyboardLocker in System Settings → Privacy & Security → Accessibility, then re-run `klock request-access`.")
    #expect(result.stderr == [])
    #expect(client.requestAccessibilityPermissionCalls == 1)
  }

  @Test
  func requestAccessFailureReportsErrorOnStandardError() async {
    let client = FakeKlockClient()
    client.requestAccessibilityPermissionResult = .failure(Self.makeError("prompt failed"))

    let result = await runKlock(arguments: ["request-access"], client: client)

    #expect(result.exitCode == 1)
    #expect(result.stdout == [])
    #expect(result.stderr == ["Error: prompt failed"])
  }

  // MARK: - Register Agent

  @Test
  func registerAgentReportsAlreadyReachableWithoutOpeningApp() async {
    let client = FakeKlockClient()
    var openCalls = 0

    let result = await runKlock(
      arguments: ["register-agent"],
      client: client,
      openKeyboardLockerApp: { openCalls += 1 }
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout == ["The KeyboardLocker agent is already registered and reachable."])
    #expect(result.stderr == [])
    #expect(openCalls == 0)
    #expect(client.statusCalls == 1)
  }

  @Test
  func registerAgentOpensAppAndConfirmsWhenAgentBecomesReachable() async {
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

    #expect(result.exitCode == 0)
    #expect(result.stdout == [
      "Launched KeyboardLocker to register its background agent.",
      "The KeyboardLocker agent is registered and reachable.",
    ])
    #expect(result.stderr == [])
    #expect(openCalls == 1)
    #expect(client.statusCalls == 2)
  }

  @Test
  func registerAgentFailsWhenAgentStaysUnreachable() async {
    let client = FakeKlockClient()
    client.statusResult = .failure(Self.makeError("unreachable"))
    var openCalls = 0

    let result = await runKlock(
      arguments: ["register-agent"],
      client: client,
      openKeyboardLockerApp: { openCalls += 1 },
      agentPoll: (attempts: 2, interval: .zero)
    )

    #expect(result.exitCode == 1)
    #expect(result.stdout == ["Launched KeyboardLocker to register its background agent."])
    #expect(result.stderr.first == "Error: The KeyboardLocker agent is not reachable yet.")
    #expect(openCalls == 1)
    #expect(client.statusCalls == 3)
  }

  @Test
  func registerAgentReportsOpenFailure() async throws {
    let client = FakeKlockClient()
    client.statusResult = .failure(Self.makeError("unreachable"))
    let error = KlockAppOpener.OpenerError.appNotFound

    let result = await runKlock(
      arguments: ["register-agent"],
      client: client,
      openKeyboardLockerApp: { throw error }
    )

    #expect(result.exitCode == 1)
    #expect(result.stdout == [])
    #expect(try result.stderr == [
      "Error: \(error.localizedDescription)",
      "  \(#require(error.recoverySuggestion))",
    ])
  }

  // MARK: - Termination Guard

  @Test
  func interactiveLockInstallsAndCancelsTerminationGuardWhileWaiting() async {
    let client = FakeKlockClient()
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 0)
    #expect(terminationGuard.installCalls == 1)
    #expect(terminationGuard.cancelCalls == 1)
  }

  @Test
  func signalDuringAcquisitionReleasesConfirmedLockBeforeTerminating() async {
    let client = FakeKlockClient()
    let terminationGuard = FakeKlockTerminationGuard()
    client.onLockInteractively = {
      terminationGuard.send(SIGTERM)
    }

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 128 + SIGTERM)
    #expect(client.unlockCalls == 1)
    #expect(terminationGuard.installCalls == 1)
    #expect(terminationGuard.cancelCalls == 1)
  }

  @Test
  func signalDuringUnlockWaitWinsOverConcurrentNormalCompletion() async {
    let client = FakeKlockClient()
    let terminationGuard = FakeKlockTerminationGuard()
    client.onWaitUntilUnlocked = {
      terminationGuard.send(SIGTERM)
    }

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 128 + SIGTERM)
    #expect(client.waitUntilUnlockedCalls == 1)
    #expect(client.unlockCalls == 1)
    #expect(terminationGuard.installCalls == 1)
    #expect(terminationGuard.cancelCalls == 1)
  }

  @Test
  func interactiveLockAlreadyLockedInstallsAndCancelsTerminationGuard() async {
    let client = FakeKlockClient()
    client.lockInteractivelyResult = .success(.alreadyLocked)
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 0)
    #expect(client.unlockCalls == 0)
    #expect(terminationGuard.installCalls == 1)
    #expect(terminationGuard.cancelCalls == 1)
  }

  @Test
  func interactiveLockFailureInstallsAndCancelsTerminationGuard() async {
    let client = FakeKlockClient()
    client.lockInteractivelyResult = .failure(Self.makeError("lock failed"))
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 1)
    #expect(client.unlockCalls == 0)
    #expect(terminationGuard.installCalls == 1)
    #expect(terminationGuard.cancelCalls == 1)
  }

  @Test
  func signalDuringAlreadyLockedAcquisitionDoesNotUnlockExistingLock() async {
    let client = FakeKlockClient()
    client.lockInteractivelyResult = .success(.alreadyLocked)
    let terminationGuard = FakeKlockTerminationGuard()
    client.onLockInteractively = {
      terminationGuard.send(SIGTERM)
    }

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 128 + SIGTERM)
    #expect(client.unlockCalls == 0)
    #expect(terminationGuard.installCalls == 1)
    #expect(terminationGuard.cancelCalls == 1)
  }

  @Test
  func signalDuringFailedAcquisitionDoesNotUnlock() async {
    let client = FakeKlockClient()
    client.lockInteractivelyResult = .failure(Self.makeError("lock failed"))
    let terminationGuard = FakeKlockTerminationGuard()
    client.onLockInteractively = {
      terminationGuard.send(SIGHUP)
    }

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 128 + SIGHUP)
    #expect(client.unlockCalls == 0)
    #expect(terminationGuard.installCalls == 1)
    #expect(terminationGuard.cancelCalls == 1)
  }

  @Test
  func interactiveLockWaitFailureCancelsTerminationGuard() async {
    let client = FakeKlockClient()
    client.waitUntilUnlockedResult = .failure(Self.makeError("wait failed"))
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 1)
    #expect(terminationGuard.installCalls == 1)
    #expect(terminationGuard.cancelCalls == 1)
  }

  @Test
  func nonInteractiveLockSkipsTerminationGuard() async {
    let client = FakeKlockClient()
    let terminationGuard = FakeKlockTerminationGuard()

    let result = await runKlock(
      arguments: ["lock", "--no-wait"],
      client: client,
      terminationGuard: terminationGuard
    )

    #expect(result.exitCode == 0)
    #expect(terminationGuard.installCalls == 0)
  }

  @Test
  func unlockBeforeTerminationReleasesCreatedLock() async {
    let client = FakeKlockClient()
    var stderr: [String] = []

    await KlockCLI.unlockBeforeTermination(client: client, printError: { stderr.append($0) })

    #expect(client.unlockCalls == 1)
    #expect(stderr == ["Terminated; released the keyboard lock created by this command."])
  }

  @Test
  func unlockBeforeTerminationReportsFailureWithRecoveryHint() async {
    let client = FakeKlockClient()
    client.unlockResult = .failure(Self.makeError("agent gone"))
    var stderr: [String] = []

    await KlockCLI.unlockBeforeTermination(client: client, printError: { stderr.append($0) })

    #expect(client.unlockCalls == 1)
    #expect(stderr.count == 1)
    #expect(stderr[0].contains("could not release"), "stderr: \(stderr)")
    #expect(stderr[0].contains("agent gone"), "stderr: \(stderr)")
    #expect(stderr[0].contains("Unlock Now"), "stderr: \(stderr)")
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
    accessPoll: (attempts: Int, interval: Duration) = (attempts: 1, interval: .zero),
    terminationGuard: any KlockTerminationGuarding = NullKlockTerminationGuard()
  ) async -> (exitCode: Int32, stdout: [String], stderr: [String]) {
    var stdout: [String] = []
    var stderr: [String] = []
    let exitCode = await KlockCLI.run(
      arguments: arguments,
      client: client,
      openKeyboardLockerApp: openKeyboardLockerApp,
      agentPoll: agentPoll,
      accessPoll: accessPoll,
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
  var toggleResult: Result<Bool, Error> = .success(true)
  /// Same scripting seam as `statusResults`: each `toggle()` consumes the next queued result
  /// before falling back to `toggleResult`, so tests can drive a state round trip.
  var toggleResults: [Result<Bool, Error>]?
  var statusResult: Result<Bool, Error> = .success(false)
  /// When set, each `status()` call consumes the next queued result before falling back to
  /// `statusResult`, so tests can script an Agent that becomes reachable after registration.
  var statusResults: [Result<Bool, Error>]?
  var lockStatusSnapshotResult: Result<LockStatusSnapshot, Error> = .success(
    LockStatusSnapshot(
      capturedAt: Date(timeIntervalSince1970: 0),
      isLocked: false,
      startedAt: nil,
      autoUnlockTargetDate: nil,
      settings: .testFixture
    )
  )
  var waitUntilUnlockedResult: Result<Void, Error> = .success(())
  var hasAccessibilityPermissionResult: Result<Bool, Error> = .success(false)
  /// Same scripting seam as `statusResults`: drives the request-access pre-check and polls.
  var hasAccessibilityPermissionResults: [Result<Bool, Error>]?
  var requestAccessibilityPermissionResult: Result<Void, Error> = .success(())
  var onLockInteractively: (() -> Void)?
  var onWaitUntilUnlocked: (() -> Void)?

  private(set) var currentSettingsCalls = 0
  private(set) var lockInteractivelyCalls = 0
  private(set) var lockCalls = 0
  private(set) var unlockCalls = 0
  private(set) var toggleCalls = 0
  private(set) var statusCalls = 0
  private(set) var lockStatusSnapshotCalls = 0
  private(set) var waitUntilUnlockedCalls = 0
  private(set) var hasAccessibilityPermissionCalls = 0
  private(set) var requestAccessibilityPermissionCalls = 0

  func currentSettings() async throws -> KeyboardLockerSettings {
    currentSettingsCalls += 1
    return try settingsResult.get()
  }

  func lockInteractively() async throws -> LockRequestOutcome {
    lockInteractivelyCalls += 1
    onLockInteractively?()
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

  func toggle() async throws -> Bool {
    toggleCalls += 1
    if toggleResults?.isEmpty == false {
      return try toggleResults!.removeFirst().get()
    }
    return try toggleResult.get()
  }

  func status() async throws -> Bool {
    statusCalls += 1
    if statusResults?.isEmpty == false {
      return try statusResults!.removeFirst().get()
    }
    return try statusResult.get()
  }

  func lockStatusSnapshot() async throws -> LockStatusSnapshot {
    lockStatusSnapshotCalls += 1
    return try lockStatusSnapshotResult.get()
  }

  func waitUntilUnlocked() async throws {
    waitUntilUnlockedCalls += 1
    onWaitUntilUnlocked?()
    try waitUntilUnlockedResult.get()
  }

  func hasAccessibilityPermission() async throws -> Bool {
    hasAccessibilityPermissionCalls += 1
    if hasAccessibilityPermissionResults?.isEmpty == false {
      return try hasAccessibilityPermissionResults!.removeFirst().get()
    }
    return try hasAccessibilityPermissionResult.get()
  }

  func requestAccessibilityPermission() async throws {
    requestAccessibilityPermissionCalls += 1
    try requestAccessibilityPermissionResult.get()
  }
}

private final class FakeKlockTerminationGuard: KlockTerminationGuarding, @unchecked Sendable {
  private(set) var installCalls = 0
  private(set) var cancelCalls = 0
  private var onTermination: ((Int32) -> Void)?

  func install(onTermination: @escaping (Int32) -> Void) -> () -> Void {
    installCalls += 1
    self.onTermination = onTermination
    return { [self] in
      cancelCalls += 1
      self.onTermination = nil
    }
  }

  func send(_ signal: Int32) {
    onTermination?(signal)
  }
}

/// Default guard for tests that do not exercise the termination path: never touches process
/// signal state, so the test process keeps its default signal dispositions.
private struct NullKlockTerminationGuard: KlockTerminationGuarding {
  func install(onTermination _: @escaping (Int32) -> Void) -> () -> Void {
    {}
  }
}
