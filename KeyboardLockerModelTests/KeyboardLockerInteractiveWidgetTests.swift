import Testing

@Suite(.serialized)
struct KeyboardLockerInteractiveWidgetTests {
  @Test
  func intentUsesExplicitLockedStateThenReloads() async throws {
    let recorder = CallRecorder()
    let intent = SetKeyboardLockWidgetIntent(
      desiredIsLocked: true,
      action: makeAction(recorder: recorder)
    )

    _ = try await intent.perform()

    let calls = await recorder.calls
    #expect(calls == [.lock, .reload])
  }

  @Test
  func intentUsesExplicitUnlockedStateThenReloads() async throws {
    let recorder = CallRecorder()
    let intent = SetKeyboardLockWidgetIntent(
      desiredIsLocked: false,
      action: makeAction(recorder: recorder)
    )

    _ = try await intent.perform()

    let calls = await recorder.calls
    #expect(calls == [.unlock, .reload])
  }

  @Test
  func intentPropagatesFailureWithoutReloading() async {
    let recorder = CallRecorder()
    let intent = SetKeyboardLockWidgetIntent(
      desiredIsLocked: true,
      action: KeyboardLockerControlAction(
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
    )

    do {
      _ = try await intent.perform()
      Issue.record("Expected the intent to propagate the Agent failure.")
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

private extension KeyboardLockerInteractiveWidgetTests {
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
