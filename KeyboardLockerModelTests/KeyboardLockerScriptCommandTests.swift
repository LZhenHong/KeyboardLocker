import Client
import Foundation
import Testing

@Suite(.serialized)
struct KeyboardLockerScriptCommandTests {
  @Test
  @MainActor
  func lockCommandInvokesOnlyLockCapability() async throws {
    let client = FakeAppleScriptAgentClient(isLocked: false)

    let result = try await LockKeyboardScriptCommand.perform(using: client)

    #expect(result == nil)
    #expect(client.lockCallCount == 1)
    #expect(client.unlockCallCount == 0)
    #expect(client.statusCallCount == 0)
    #expect(client.isLocked)
  }

  @Test
  @MainActor
  func unlockCommandInvokesOnlyUnlockCapability() async throws {
    let client = FakeAppleScriptAgentClient(isLocked: true)

    let result = try await UnlockKeyboardScriptCommand.perform(using: client)

    #expect(result == nil)
    #expect(client.lockCallCount == 0)
    #expect(client.unlockCallCount == 1)
    #expect(client.statusCallCount == 0)
    #expect(!client.isLocked)
  }

  @Test
  @MainActor
  func statusCommandReturnsAuthoritativeBoolean() async throws {
    let client = FakeAppleScriptAgentClient(isLocked: true)

    let result = try await GetKeyboardLockStatusScriptCommand.perform(using: client)

    #expect(result as? NSNumber == NSNumber(value: true))
    #expect(client.lockCallCount == 0)
    #expect(client.unlockCallCount == 0)
    #expect(client.statusCallCount == 1)
  }

  @Test
  @MainActor
  func commandPropagatesAgentFailure() async {
    let client = FakeAppleScriptAgentClient(
      isLocked: false,
      error: AppleScriptClientError.unavailable
    )

    do {
      _ = try await LockKeyboardScriptCommand.perform(using: client)
      Issue.record("Expected the Agent error to be propagated.")
    } catch {
      #expect(error as? AppleScriptClientError == .unavailable)
    }
  }

  @Test
  @MainActor
  func errorPresentationIncludesClientRecoverySuggestion() {
    let message = AppleScriptErrorPresentation.message(
      for: XPCClientError.serviceUnavailable
    )

    #expect(
      message ==
        ExternalAutomationFailure(error: XPCClientError.serviceUnavailable).message
    )
    #expect(message.contains("The KeyboardLocker agent is not reachable."))
    #expect(message.contains("Open KeyboardLocker once"))
  }

  @Test
  @MainActor
  func errorPresentationUsesAppleEventTimeoutOnlyForClientTimeout() {
    #expect(
      AppleScriptErrorPresentation.errorNumber(for: XPCClientError.timedOut) ==
        Int(errAETimeout)
    )
    #expect(
      AppleScriptErrorPresentation.errorNumber(for: XPCClientError.serviceUnavailable) ==
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
