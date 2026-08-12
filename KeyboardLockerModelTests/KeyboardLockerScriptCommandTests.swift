import Client
import Foundation
import XCTest

final class KeyboardLockerScriptCommandTests: XCTestCase {
  @MainActor
  func testLockCommandInvokesOnlyLockCapability() async throws {
    let client = FakeAppleScriptAgentClient(isLocked: false)

    let result = try await LockKeyboardScriptCommand.perform(using: client)

    XCTAssertNil(result)
    XCTAssertEqual(client.lockCallCount, 1)
    XCTAssertEqual(client.unlockCallCount, 0)
    XCTAssertEqual(client.statusCallCount, 0)
    XCTAssertTrue(client.isLocked)
  }

  @MainActor
  func testUnlockCommandInvokesOnlyUnlockCapability() async throws {
    let client = FakeAppleScriptAgentClient(isLocked: true)

    let result = try await UnlockKeyboardScriptCommand.perform(using: client)

    XCTAssertNil(result)
    XCTAssertEqual(client.lockCallCount, 0)
    XCTAssertEqual(client.unlockCallCount, 1)
    XCTAssertEqual(client.statusCallCount, 0)
    XCTAssertFalse(client.isLocked)
  }

  @MainActor
  func testStatusCommandReturnsAuthoritativeBoolean() async throws {
    let client = FakeAppleScriptAgentClient(isLocked: true)

    let result = try await GetKeyboardLockStatusScriptCommand.perform(using: client)

    XCTAssertEqual(result as? NSNumber, NSNumber(value: true))
    XCTAssertEqual(client.lockCallCount, 0)
    XCTAssertEqual(client.unlockCallCount, 0)
    XCTAssertEqual(client.statusCallCount, 1)
  }

  @MainActor
  func testCommandPropagatesAgentFailure() async {
    let client = FakeAppleScriptAgentClient(
      isLocked: false,
      error: AppleScriptClientError.unavailable
    )

    do {
      _ = try await LockKeyboardScriptCommand.perform(using: client)
      XCTFail("Expected the Agent error to be propagated.")
    } catch {
      XCTAssertEqual(error as? AppleScriptClientError, .unavailable)
    }
  }

  @MainActor
  func testErrorPresentationIncludesClientRecoverySuggestion() {
    let message = AppleScriptErrorPresentation.message(
      for: XPCClientError.serviceUnavailable
    )

    XCTAssertEqual(
      message,
      ExternalAutomationFailure(error: XPCClientError.serviceUnavailable).message
    )
    XCTAssertTrue(message.contains("The KeyboardLocker agent is not reachable."))
    XCTAssertTrue(message.contains("Open KeyboardLocker once"))
  }

  @MainActor
  func testErrorPresentationUsesAppleEventTimeoutOnlyForClientTimeout() {
    XCTAssertEqual(
      AppleScriptErrorPresentation.errorNumber(for: XPCClientError.timedOut),
      Int(errAETimeout)
    )
    XCTAssertEqual(
      AppleScriptErrorPresentation.errorNumber(for: XPCClientError.serviceUnavailable),
      Int(errAEEventFailed)
    )
  }
}

@MainActor
private final class FakeAppleScriptAgentClient: AgentLockActionServing {
  private(set) var lockCallCount = 0
  private(set) var statusCallCount = 0
  private(set) var unlockCallCount = 0
  private(set) var isLocked: Bool

  private let error: Error?

  init(isLocked: Bool, error: Error? = nil) {
    self.isLocked = isLocked
    self.error = error
  }

  func lock() async throws {
    try throwConfiguredError()
    lockCallCount += 1
    isLocked = true
  }

  func unlock() async throws {
    try throwConfiguredError()
    unlockCallCount += 1
    isLocked = false
  }

  func status() async throws -> Bool {
    try throwConfiguredError()
    statusCallCount += 1
    return isLocked
  }

  func toggle() async throws -> Bool {
    try throwConfiguredError()
    isLocked.toggle()
    return isLocked
  }

  private func throwConfiguredError() throws {
    if let error {
      throw error
    }
  }
}

private enum AppleScriptClientError: Error, Equatable {
  case unavailable
}
