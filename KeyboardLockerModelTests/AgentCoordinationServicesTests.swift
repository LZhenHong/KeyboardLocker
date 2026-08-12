import Client
import Foundation
import SystemSurfaces
import Testing

@Suite(.serialized)
struct AgentCoordinationServicesTests {
  @Test
  @MainActor
  func successfulLockInvalidatesWidgetThenControl() async throws {
    let recorder = CallRecorder()
    let client = makeClient(recorder: recorder)

    try await client.lock()

    #expect(recorder.calls == [.lock, .widget, .control])
  }

  @Test
  @MainActor
  func successfulUnlockInvalidatesWidgetThenControl() async throws {
    let recorder = CallRecorder()
    let client = makeClient(recorder: recorder)

    try await client.unlock()

    #expect(recorder.calls == [.unlock, .widget, .control])
  }

  @Test
  @MainActor
  func failedMutationDoesNotInvalidateSurfaces() async {
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
      toggle: {
        recorder.record(.toggle)
        return true
      },
      surfaceInvalidator: makeInvalidator(recorder: recorder)
    )

    do {
      try await client.lock()
      Issue.record("Expected the Agent failure to propagate.")
    } catch {
      #expect(error as? TestError == .expected)
    }

    #expect(recorder.calls == [.lock])
  }

  @Test
  @MainActor
  func failedUnlockDoesNotInvalidateSurfaces() async {
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
      toggle: {
        recorder.record(.toggle)
        return true
      },
      surfaceInvalidator: makeInvalidator(recorder: recorder)
    )

    do {
      try await client.unlock()
      Issue.record("Expected the Agent failure to propagate.")
    } catch {
      #expect(error as? TestError == .expected)
    }

    #expect(recorder.calls == [.unlock])
  }

  @Test
  @MainActor
  func statusDoesNotInvalidateSurfaces() async throws {
    let recorder = CallRecorder()
    let client = makeClient(recorder: recorder, status: true)

    let isLocked = try await client.status()

    #expect(isLocked)
    #expect(recorder.calls == [.status])
  }

  @Test
  @MainActor
  func successfulToggleInvalidatesWidgetThenControl() async throws {
    let recorder = CallRecorder()
    let client = makeClient(recorder: recorder)

    let isLocked = try await client.toggle()

    #expect(isLocked)
    #expect(recorder.calls == [.toggle, .widget, .control])
  }

  @Test
  @MainActor
  func successfulSafetyCheckInvalidatesWidgetThenControl() async throws {
    let recorder = CallRecorder()
    let client = makeClient(recorder: recorder)

    let outcome = try await client.beginSafetyCheck()

    #expect(outcome == .acquired)
    #expect(recorder.calls == [.safetyCheck, .widget, .control])
  }

  @Test
  @MainActor
  func failedToggleDoesNotInvalidateSurfaces() async {
    let recorder = CallRecorder()
    let client = LiveAgentClient(
      lock: {
        recorder.record(.lock)
      },
      unlock: {
        recorder.record(.unlock)
      },
      status: {
        recorder.record(.status)
        return false
      },
      toggle: {
        recorder.record(.toggle)
        throw TestError.expected
      },
      surfaceInvalidator: makeInvalidator(recorder: recorder)
    )

    do {
      _ = try await client.toggle()
      Issue.record("Expected the Agent failure to propagate.")
    } catch {
      #expect(error as? TestError == .expected)
    }

    #expect(recorder.calls == [.toggle])
  }

  @Test
  @MainActor
  func liveObserverInvalidatesAtSubscriptionAndBeforeForwardingAChange() {
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

    #expect(base.initialStates == [false])
    #expect(recorder.calls == [.widget, .control])

    base.send(true)

    #expect(receivedValues == [true])
    #expect(recorder.calls == [.widget, .control, .widget, .control])
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
      toggle: {
        recorder.record(.toggle)
        return true
      },
      beginSafetyCheck: {
        recorder.record(.safetyCheck)
        return .acquired
      },
      waitUntilUnlocked: {},
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
    case safetyCheck
    case status
    case toggle
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
