import Foundation
@testable import SystemSurfaces
import XCTest

final class LockStateSurfaceInvalidatorTests: XCTestCase {
  func testSurfaceKindsRemainStable() {
    XCTAssertEqual(
      KeyboardLockerSurfaceKind.statusWidget,
      "io.lzhlovesjyq.keyboardlocker.status"
    )
    XCTAssertEqual(
      KeyboardLockerSurfaceKind.keyboardLockControl,
      "io.lzhlovesjyq.keyboardlocker.control"
    )
  }

  func testInvalidationReloadsWidgetThenControlExactlyOnce() {
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

    XCTAssertEqual(recorder.calls, [.widget, .control])
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
