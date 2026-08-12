import Foundation
@testable import SystemSurfaces
import Testing

@Suite(.serialized)
struct LockStateSurfaceInvalidatorTests {
  @Test
  func surfaceKindsRemainStable() {
    #expect(
      KeyboardLockerSurfaceKind.statusWidget == "io.lzhlovesjyq.keyboardlocker.status"
    )
    #expect(
      KeyboardLockerSurfaceKind.keyboardLockControl == "io.lzhlovesjyq.keyboardlocker.control"
    )
  }

  @Test
  func invalidationReloadsWidgetThenControlExactlyOnce() {
    let recorder = CallRecorder()
    let invalidator = LockStateSurfaceInvalidator(
      reloadWidget: {
        recorder.record(.widget)
      },
      reloadControl: {
        recorder.record(.control)
      }
    )

    invalidator.invalidate()

    #expect(recorder.calls == [.widget, .control])
  }
}

private final class CallRecorder: @unchecked Sendable {
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

  func record(_ call: Call) {
    lock.lock()
    recordedCalls.append(call)
    lock.unlock()
  }
}
