import AppIntents
import Testing

@Suite(.serialized)
struct KeyboardLockAppIntentTests {
  @Test
  @MainActor
  func lockIntentInvokesOnlyLockCapability() async throws {
    let client = FakeAgentLockActionClient(isLocked: false)

    _ = try await LockKeyboardIntent(client: client).perform()

    #expect(client.lockCallCount == 1)
    #expect(client.unlockCallCount == 0)
    #expect(client.statusCallCount == 0)
    #expect(client.isLocked)
  }

  @Test
  @MainActor
  func unlockIntentInvokesOnlyUnlockCapability() async throws {
    let client = FakeAgentLockActionClient(isLocked: true)

    _ = try await UnlockKeyboardIntent(client: client).perform()

    #expect(client.lockCallCount == 0)
    #expect(client.unlockCallCount == 1)
    #expect(client.statusCallCount == 0)
    #expect(!client.isLocked)
  }

  @Test
  @MainActor
  func statusIntentReturnsAuthoritativeClientValue() async throws {
    let client = FakeAgentLockActionClient(isLocked: true)

    let result = try await GetKeyboardLockStatusIntent(client: client).perform()

    #expect(result.value == true)
    #expect(client.lockCallCount == 0)
    #expect(client.unlockCallCount == 0)
    #expect(client.statusCallCount == 1)
  }

  @Test
  @MainActor
  func statusIntentPropagatesAgentFailureWithoutFallback() async {
    let client = FakeAgentLockActionClient(
      isLocked: false,
      error: IntentClientError.unavailable
    )

    do {
      _ = try await GetKeyboardLockStatusIntent(client: client).perform()
      Issue.record("Expected the Agent error to be propagated.")
    } catch {
      #expect(error as? IntentClientError == .unavailable)
    }
  }

  @Test
  @MainActor
  func toggleIntentFromUnlockedReturnsLocked() async throws {
    let client = FakeAgentLockActionClient(isLocked: false)

    let result = try await ToggleKeyboardLockIntent(client: client).perform()

    #expect(result.value == true)
    #expect(client.toggleCallCount == 1)
    #expect(client.lockCallCount == 0)
    #expect(client.unlockCallCount == 0)
    #expect(client.statusCallCount == 0)
    #expect(client.isLocked)
  }

  @Test
  @MainActor
  func toggleIntentFromLockedReturnsUnlocked() async throws {
    let client = FakeAgentLockActionClient(isLocked: true)

    let result = try await ToggleKeyboardLockIntent(client: client).perform()

    #expect(result.value == false)
    #expect(client.toggleCallCount == 1)
    #expect(!client.isLocked)
  }

  @Test
  @MainActor
  func toggleIntentPropagatesAgentFailureWithoutFallback() async {
    let client = FakeAgentLockActionClient(
      isLocked: false,
      error: IntentClientError.unavailable
    )

    do {
      _ = try await ToggleKeyboardLockIntent(client: client).perform()
      Issue.record("Expected the Agent error to be propagated.")
    } catch {
      #expect(error as? IntentClientError == .unavailable)
      #expect(!client.isLocked)
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
