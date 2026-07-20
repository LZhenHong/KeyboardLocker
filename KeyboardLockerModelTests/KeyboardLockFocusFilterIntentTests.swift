import Foundation
import SystemSurfaces
import XCTest

final class KeyboardLockFocusFilterIntentTests: XCTestCase {
  func testDefaultFilterDoesNotRequestALock() {
    XCTAssertFalse(KeyboardLockFocusFilterIntent().lockKeyboard)
  }

  func testEnabledFilterForwardsTrueToAgent() async throws {
    let client = FakeAgentFocusLockClient()
    let surfaces = FocusSurfaceRecorder()

    _ = try await KeyboardLockFocusFilterIntent(
      lockKeyboard: true,
      client: client,
      surfaceInvalidator: surfaces.invalidator
    ).perform()

    let receivedValues = await client.receivedValues
    XCTAssertEqual(receivedValues, [true])
    XCTAssertEqual(surfaces.calls, [.widget, .control])
  }

  func testDisabledFilterForwardsFalseToAgent() async throws {
    let client = FakeAgentFocusLockClient()
    let surfaces = FocusSurfaceRecorder()

    _ = try await KeyboardLockFocusFilterIntent(
      lockKeyboard: false,
      client: client,
      surfaceInvalidator: surfaces.invalidator
    ).perform()

    let receivedValues = await client.receivedValues
    XCTAssertEqual(receivedValues, [false])
    XCTAssertEqual(surfaces.calls, [.widget, .control])
  }

  func testAgentFailureIsPropagated() async {
    let client = FakeAgentFocusLockClient(error: FocusIntentTestError.unavailable)
    let surfaces = FocusSurfaceRecorder()

    do {
      _ = try await KeyboardLockFocusFilterIntent(
        lockKeyboard: true,
        client: client,
        surfaceInvalidator: surfaces.invalidator
      ).perform()
      XCTFail("Expected the Agent error to be propagated.")
    } catch {
      XCTAssertEqual(error as? FocusIntentTestError, .unavailable)
    }

    XCTAssertTrue(surfaces.calls.isEmpty)
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

private final class FocusSurfaceRecorder: @unchecked Sendable {
  enum Call: Equatable {
    case control
    case widget
  }

  private let lock = NSLock()
  private var recordedCalls: [Call] = []

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return recordedCalls
  }

  var invalidator: LockStateSurfaceInvalidator {
    LockStateSurfaceInvalidator(
      reloadWidget: {
        self.record(.widget)
      },
      reloadControl: {
        self.record(.control)
      }
    )
  }

  private func record(_ call: Call) {
    lock.lock()
    recordedCalls.append(call)
    lock.unlock()
  }
}
