import Client
import Foundation
import SystemSurfaces
import XCTest

final class AgentCoordinationServicesTests: XCTestCase {
  @MainActor
  func testSuccessfulLockInvalidatesWidgetThenControl() async throws {
    let recorder = CallRecorder()
    let client = makeClient(recorder: recorder)

    try await client.lock()

    XCTAssertEqual(recorder.calls, [.lock, .widget, .control])
  }

  @MainActor
  func testSuccessfulUnlockInvalidatesWidgetThenControl() async throws {
    let recorder = CallRecorder()
    let client = makeClient(recorder: recorder)

    try await client.unlock()

    XCTAssertEqual(recorder.calls, [.unlock, .widget, .control])
  }

  @MainActor
  func testFailedMutationDoesNotInvalidateSurfaces() async {
    let recorder = CallRecorder()
    let client = LiveAgentClient(
      lock: {
        recorder.record(.lock)
        throw TestError.expected
      },
      unlock: {
        recorder.record(.unlock)
      },
      status: {
        recorder.record(.status)
        return false
      },
      surfaceInvalidator: makeInvalidator(recorder: recorder)
    )

    do {
      try await client.lock()
      XCTFail("Expected the Agent failure to propagate.")
    } catch {
      XCTAssertEqual(error as? TestError, .expected)
    }

    XCTAssertEqual(recorder.calls, [.lock])
  }

  @MainActor
  func testFailedUnlockDoesNotInvalidateSurfaces() async {
    let recorder = CallRecorder()
    let client = LiveAgentClient(
      lock: {
        recorder.record(.lock)
      },
      unlock: {
        recorder.record(.unlock)
        throw TestError.expected
      },
      status: {
        recorder.record(.status)
        return false
      },
      surfaceInvalidator: makeInvalidator(recorder: recorder)
    )

    do {
      try await client.unlock()
      XCTFail("Expected the Agent failure to propagate.")
    } catch {
      XCTAssertEqual(error as? TestError, .expected)
    }

    XCTAssertEqual(recorder.calls, [.unlock])
  }

  @MainActor
  func testStatusDoesNotInvalidateSurfaces() async throws {
    let recorder = CallRecorder()
    let client = makeClient(recorder: recorder, status: true)

    let isLocked = try await client.status()

    XCTAssertTrue(isLocked)
    XCTAssertEqual(recorder.calls, [.status])
  }

  @MainActor
  func testLiveObserverInvalidatesAtSubscriptionAndBeforeForwardingAChange() {
    let recorder = CallRecorder()
    let base = RecordingLockStateObserver()
    let observer = LiveAgentLockStateObserver(
      observer: base,
      surfaceInvalidator: makeInvalidator(recorder: recorder)
    )
    var receivedValues: [Bool] = []

    let token = observer.subscribe(initialState: false) { isLocked in
      receivedValues.append(isLocked)
    }

    XCTAssertEqual(base.initialStates, [false])
    XCTAssertEqual(recorder.calls, [.widget, .control])

    base.send(true)

    XCTAssertEqual(receivedValues, [true])
    XCTAssertEqual(recorder.calls, [.widget, .control, .widget, .control])
    withExtendedLifetime(token) {}
  }

  @MainActor
  private func makeClient(
    recorder: CallRecorder,
    status: Bool = false
  ) -> LiveAgentClient {
    LiveAgentClient(
      lock: {
        recorder.record(.lock)
      },
      unlock: {
        recorder.record(.unlock)
      },
      status: {
        recorder.record(.status)
        return status
      },
      surfaceInvalidator: makeInvalidator(recorder: recorder)
    )
  }
}

private extension AgentCoordinationServicesTests {
  enum TestError: Error {
    case expected
  }

  func makeInvalidator(recorder: CallRecorder) -> LockStateSurfaceInvalidator {
    LockStateSurfaceInvalidator(
      reloadWidget: {
        recorder.record(.widget)
      },
      reloadControl: {
        recorder.record(.control)
      }
    )
  }
}

private final class CallRecorder: @unchecked Sendable {
  enum Call: Equatable {
    case control
    case lock
    case status
    case unlock
    case widget
  }

  private let lock = NSLock()
  private var recordedCalls: [Call] = []

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return recordedCalls
  }

  func record(_ call: Call) {
    lock.lock()
    recordedCalls.append(call)
    lock.unlock()
  }
}

@MainActor
private final class RecordingLockStateObserver: AgentLockStateObserving {
  private(set) var initialStates: [Bool?] = []
  private var handler: ((Bool) -> Void)?

  func subscribe(
    initialState: Bool?,
    _ handler: @escaping (Bool) -> Void
  ) -> ObserverToken {
    initialStates.append(initialState)
    self.handler = handler
    return ObserverToken {}
  }

  func send(_ isLocked: Bool) {
    handler?(isLocked)
  }
}
