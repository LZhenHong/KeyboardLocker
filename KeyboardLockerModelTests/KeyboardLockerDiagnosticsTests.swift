import Client
import Foundation
import XCTest

final class KeyboardLockerDiagnosticsTests: XCTestCase {
  @MainActor
  func testReportIncludesRuntimeFactsWithoutMachineIdentity() async {
    let descriptor = ServiceDescriptor(
      protocolVersion: ServiceProtocolVersion(major: 1, minor: 7),
      capabilities: [.lockControl, .safetyCheckLock],
      agentBundleIdentifier: SharedConstants.agentBundleIdentifier,
      agentVersion: "1.2",
      agentBuild: "34",
      agentInstanceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )
    let lockSnapshot = LockStatusSnapshot(
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      isLocked: false,
      startedAt: nil,
      autoUnlockTargetDate: nil,
      settings: .default
    )
    let collector = KeyboardLockerDiagnosticsCollector(
      appIdentity: .init(
        build: "12",
        bundleIdentifier: SharedConstants.appBundleIdentifier,
        version: "1.1"
      ),
      operatingSystemVersion: "macOS 26.0",
      registrationStatus: { "enabled" },
      descriptor: { descriptor },
      accessibility: { true },
      lockSnapshot: { lockSnapshot },
      now: { Date(timeIntervalSince1970: 1_700_000_100) }
    )
    let appSnapshot = AppCoordinator.Snapshot(
      state: .ready(isLocked: false),
      activity: nil,
      lastError: nil,
      safetyCheckState: .completed
    )

    let report = await collector.report(appSnapshot: appSnapshot)

    XCTAssertTrue(report.contains("App: 1.1 (12)"))
    XCTAssertTrue(report.contains("Agent Registration: enabled"))
    XCTAssertTrue(report.contains("Protocol: 1.7"))
    XCTAssertTrue(report.contains("Capabilities: lock-control, safety-check-lock"))
    XCTAssertTrue(report.contains("Accessibility: granted"))
    XCTAssertTrue(report.contains("Status: unlocked"))
    XCTAssertTrue(report.contains("Safety Check: completed"))
    XCTAssertFalse(report.localizedCaseInsensitiveContains("user name"))
    XCTAssertFalse(report.localizedCaseInsensitiveContains("host name"))
  }

  @MainActor
  func testReportKeepsPartialDiagnosticsAndRedactsPaths() async {
    let collector = KeyboardLockerDiagnosticsCollector(
      appIdentity: .init(build: "1", bundleIdentifier: "test.app", version: "1.0"),
      operatingSystemVersion: "macOS test",
      registrationStatus: { "not-registered" },
      descriptor: {
        throw TestError.message("Failed at /Users/example/Library/Agent.app")
      },
      accessibility: { false },
      lockSnapshot: {
        throw TestError.message("Could not open file:///private/tmp/KeyboardLocker/state")
      },
      now: { Date(timeIntervalSince1970: 0) }
    )
    let appSnapshot = AppCoordinator.Snapshot(
      state: .unavailable(message: "Missing /Applications/KeyboardLocker.app", canRestartAgent: true),
      activity: nil,
      lastError: "Missing /Applications/KeyboardLocker.app",
      safetyCheckState: .failed("Expected")
    )

    let report = await collector.report(appSnapshot: appSnapshot)

    XCTAssertTrue(report.contains("Agent Registration: not-registered"))
    XCTAssertTrue(report.contains("Accessibility: not-granted"))
    XCTAssertTrue(report.contains("<redacted-path>"))
    XCTAssertFalse(report.contains("/Users/example"))
    XCTAssertFalse(report.contains("/private/tmp"))
    XCTAssertFalse(report.contains("/Applications/KeyboardLocker.app"))
  }
}

private struct TestError: Error, LocalizedError {
  let value: String

  static func message(_ value: String) -> Self {
    Self(value: value)
  }

  var errorDescription: String? {
    value
  }
}
