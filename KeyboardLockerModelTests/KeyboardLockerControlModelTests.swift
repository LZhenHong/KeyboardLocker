import Foundation
import XCTest

final class KeyboardLockerControlModelTests: XCTestCase {
  func testValueLoaderReturnsAuthoritativeValue() async throws {
    let loader = KeyboardLockerControlValueLoader {
      true
    }

    let value = try await loader.currentValue()

    XCTAssertTrue(value)
  }

  func testValueLoaderPropagatesFailure() async {
    let loader = KeyboardLockerControlValueLoader {
      throw TestError.expected
    }

    do {
      _ = try await loader.currentValue()
      XCTFail("Expected the loader to propagate the error.")
    } catch {
      XCTAssertEqual(error as? TestError, .expected)
    }
  }

  func testSetLockedCallsOnlyLockThenReload() async throws {
    let recorder = CallRecorder()
    let action = makeAction(recorder: recorder)

    try await action.setLocked(true)

    let calls = await recorder.calls
    XCTAssertEqual(calls, [.lock, .reload])
  }

  func testSetUnlockedCallsOnlyUnlockThenReload() async throws {
    let recorder = CallRecorder()
    let action = makeAction(recorder: recorder)

    try await action.setLocked(false)

    let calls = await recorder.calls
    XCTAssertEqual(calls, [.unlock, .reload])
  }

  func testFailedActionDoesNotReload() async {
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
      XCTFail("Expected the action to propagate the error.")
    } catch {
      XCTAssertEqual(error as? TestError, .expected)
    }

    let calls = await recorder.calls
    XCTAssertEqual(calls, [.lock])
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
