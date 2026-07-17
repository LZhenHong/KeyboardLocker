import XCTest

final class KeyboardLockFocusFilterIntentTests: XCTestCase {
  func testEnabledFilterForwardsTrueToAgent() async throws {
    let client = FakeAgentFocusLockClient()

    _ = try await KeyboardLockFocusFilterIntent(
      lockKeyboard: true,
      client: client
    ).perform()

    let receivedValues = await client.receivedValues
    XCTAssertEqual(receivedValues, [true])
  }

  func testDisabledFilterForwardsFalseToAgent() async throws {
    let client = FakeAgentFocusLockClient()

    _ = try await KeyboardLockFocusFilterIntent(
      lockKeyboard: false,
      client: client
    ).perform()

    let receivedValues = await client.receivedValues
    XCTAssertEqual(receivedValues, [false])
  }

  func testAgentFailureIsPropagated() async {
    let client = FakeAgentFocusLockClient(error: FocusIntentTestError.unavailable)

    do {
      _ = try await KeyboardLockFocusFilterIntent(
        lockKeyboard: true,
        client: client
      ).perform()
      XCTFail("Expected the Agent error to be propagated.")
    } catch {
      XCTAssertEqual(error as? FocusIntentTestError, .unavailable)
    }
  }
}

private actor FakeAgentFocusLockClient: AgentFocusLockServing {
  private(set) var receivedValues: [Bool] = []

  private let error: Error?

  init(error: Error? = nil) {
    self.error = error
  }

  func setFocusFilterLockEnabled(_ enabled: Bool) async throws {
    if let error {
      throw error
    }
    receivedValues.append(enabled)
  }
}

private enum FocusIntentTestError: Error, Equatable {
  case unavailable
}
