import AppIntents
import XCTest

final class KeyboardLockAppIntentTests: XCTestCase {
  @MainActor
  func testLockIntentInvokesOnlyLockCapability() async throws {
    let client = FakeAgentLockActionClient(isLocked: false)

    _ = try await LockKeyboardIntent(client: client).perform()

    XCTAssertEqual(client.lockCallCount, 1)
    XCTAssertEqual(client.unlockCallCount, 0)
    XCTAssertEqual(client.statusCallCount, 0)
    XCTAssertTrue(client.isLocked)
  }

  @MainActor
  func testUnlockIntentInvokesOnlyUnlockCapability() async throws {
    let client = FakeAgentLockActionClient(isLocked: true)

    _ = try await UnlockKeyboardIntent(client: client).perform()

    XCTAssertEqual(client.lockCallCount, 0)
    XCTAssertEqual(client.unlockCallCount, 1)
    XCTAssertEqual(client.statusCallCount, 0)
    XCTAssertFalse(client.isLocked)
  }

  @MainActor
  func testStatusIntentReturnsAuthoritativeClientValue() async throws {
    let client = FakeAgentLockActionClient(isLocked: true)

    let result = try await GetKeyboardLockStatusIntent(client: client).perform()

    XCTAssertEqual(result.value, true)
    XCTAssertEqual(client.lockCallCount, 0)
    XCTAssertEqual(client.unlockCallCount, 0)
    XCTAssertEqual(client.statusCallCount, 1)
  }

  @MainActor
  func testStatusIntentPropagatesAgentFailureWithoutFallback() async {
    let client = FakeAgentLockActionClient(
      isLocked: false,
      error: IntentClientError.unavailable
    )

    do {
      _ = try await GetKeyboardLockStatusIntent(client: client).perform()
      XCTFail("Expected the Agent error to be propagated.")
    } catch {
      XCTAssertEqual(error as? IntentClientError, .unavailable)
    }
  }

  @MainActor
  func testToggleIntentFromUnlockedReturnsLocked() async throws {
    let client = FakeAgentLockActionClient(isLocked: false)

    let result = try await ToggleKeyboardLockIntent(client: client).perform()

    XCTAssertEqual(result.value, true)
    XCTAssertEqual(client.toggleCallCount, 1)
    XCTAssertEqual(client.lockCallCount, 0)
    XCTAssertEqual(client.unlockCallCount, 0)
    XCTAssertEqual(client.statusCallCount, 0)
    XCTAssertTrue(client.isLocked)
  }

  @MainActor
  func testToggleIntentFromLockedReturnsUnlocked() async throws {
    let client = FakeAgentLockActionClient(isLocked: true)

    let result = try await ToggleKeyboardLockIntent(client: client).perform()

    XCTAssertEqual(result.value, false)
    XCTAssertEqual(client.toggleCallCount, 1)
    XCTAssertFalse(client.isLocked)
  }

  @MainActor
  func testToggleIntentPropagatesAgentFailureWithoutFallback() async {
    let client = FakeAgentLockActionClient(
      isLocked: false,
      error: IntentClientError.unavailable
    )

    do {
      _ = try await ToggleKeyboardLockIntent(client: client).perform()
      XCTFail("Expected the Agent error to be propagated.")
    } catch {
      XCTAssertEqual(error as? IntentClientError, .unavailable)
      XCTAssertFalse(client.isLocked)
    }
  }
}

@MainActor
private final class FakeAgentLockActionClient: AgentLockActionServing {
  private(set) var lockCallCount = 0
  private(set) var statusCallCount = 0
  private(set) var toggleCallCount = 0
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
    toggleCallCount += 1
    isLocked.toggle()
    return isLocked
  }

  private func throwConfiguredError() throws {
    if let error {
      throw error
    }
  }
}

private enum IntentClientError: Error, Equatable {
  case unavailable
}
