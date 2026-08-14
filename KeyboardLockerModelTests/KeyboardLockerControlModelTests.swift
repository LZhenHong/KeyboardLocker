import Foundation
import Testing

@Suite(.serialized)
struct KeyboardLockerControlModelTests {
  @Test
  func valueLoaderReturnsAuthoritativeValue() async throws {
    let loader = KeyboardLockerControlValueLoader {
      true
    }

    let value = try await loader.currentValue()

    #expect(value)
  }

  @Test
  func valueLoaderPropagatesFailure() async {
    let loader = KeyboardLockerControlValueLoader {
      throw TestError.expected
    }

    do {
      _ = try await loader.currentValue()
      Issue.record("Expected the loader to propagate the error.")
    } catch {
      #expect(error as? TestError == .expected)
    }
  }

  @Test
  func setLockedCallsOnlyLockThenReload() async throws {
    let recorder = CallRecorder()
    let action = makeAction(recorder: recorder)

    try await action.setLocked(true)

    let calls = await recorder.calls
    #expect(calls == [.lock, .reload])
  }

  @Test
  func setUnlockedCallsOnlyUnlockThenReload() async throws {
    let recorder = CallRecorder()
    let action = makeAction(recorder: recorder)

    try await action.setLocked(false)

    let calls = await recorder.calls
    #expect(calls == [.unlock, .reload])
  }

  @Test
  func failedActionDoesNotReload() async {
    let recorder = CallRecorder()
    let action = KeyboardLockerControlAction(
      lock: {
        await recorder.record(.lock)
        throw TestError.expected
      },
      unlock: {
        await recorder.record(.unlock)
      },
      reload: {
        await recorder.record(.reload)
      }
    )

    do {
      try await action.setLocked(true)
      Issue.record("Expected the action to propagate the error.")
    } catch {
      #expect(error as? TestError == .expected)
    }

    let calls = await recorder.calls
    #expect(calls == [.lock])
  }

  private func makeAction(recorder: CallRecorder) -> KeyboardLockerControlAction {
    KeyboardLockerControlAction(
      lock: {
        await recorder.record(.lock)
      },
      unlock: {
        await recorder.record(.unlock)
      },
      reload: {
        await recorder.record(.reload)
      }
    )
  }
}

private extension KeyboardLockerControlModelTests {
  enum TestError: Error {
    case expected
  }

  enum Call: Equatable {
    case lock
    case unlock
    case reload
  }

  actor CallRecorder {
    private(set) var calls: [Call] = []

    func record(_ call: Call) {
      calls.append(call)
    }
  }
}
