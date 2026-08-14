import Foundation
import SystemSurfaces
import Testing

@Suite(.serialized)
struct KeyboardLockFocusFilterIntentTests {
  @Test
  func defaultFilterDoesNotRequestALock() {
    #expect(!KeyboardLockFocusFilterIntent().lockKeyboard)
  }

  @Test
  func enabledFilterForwardsTrueToAgent() async throws {
    let client = FakeAgentFocusLockClient()
    let surfaces = FocusSurfaceRecorder()

    _ = try await KeyboardLockFocusFilterIntent(
      lockKeyboard: true,
      client: client,
      surfaceInvalidator: surfaces.invalidator
    ).perform()

    let receivedValues = await client.receivedValues
    #expect(receivedValues == [true])
    #expect(surfaces.calls == [.widget, .control])
  }

  @Test
  func disabledFilterForwardsFalseToAgent() async throws {
    let client = FakeAgentFocusLockClient()
    let surfaces = FocusSurfaceRecorder()

    _ = try await KeyboardLockFocusFilterIntent(
      lockKeyboard: false,
      client: client,
      surfaceInvalidator: surfaces.invalidator
    ).perform()

    let receivedValues = await client.receivedValues
    #expect(receivedValues == [false])
    #expect(surfaces.calls == [.widget, .control])
  }

  @Test
  func agentFailureIsPropagated() async {
    let client = FakeAgentFocusLockClient(error: FocusIntentTestError.unavailable)
    let surfaces = FocusSurfaceRecorder()

    do {
      _ = try await KeyboardLockFocusFilterIntent(
        lockKeyboard: true,
        client: client,
        surfaceInvalidator: surfaces.invalidator
      ).perform()
      Issue.record("Expected the Agent error to be propagated.")
    } catch {
      #expect(error as? FocusIntentTestError == .unavailable)
    }

    #expect(surfaces.calls.isEmpty)
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
