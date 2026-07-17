import Common
import Foundation
@testable import Service
import XCTest

final class LockRuntimeStateTests: XCTestCase {
  func testDuplicateBeginPreservesOriginalRuntimeStateAndDeadline() {
    let originalSettings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: .init(keyCode: 12, modifierFlags: [.maskCommand])
    )
    let replacementSettings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 300),
      unlockHotkey: .init(keyCode: 13, modifierFlags: [.maskControl])
    )
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    let deadline = startedAt.addingTimeInterval(60)
    var state = LockRuntimeState()

    XCTAssertTrue(state.begin(settings: originalSettings, at: startedAt))
    state.setAutoUnlockTargetDate(deadline)

    XCTAssertFalse(
      state.begin(
        settings: replacementSettings,
        at: startedAt.addingTimeInterval(10)
      )
    )
    XCTAssertEqual(state.activeSettings, originalSettings)
    XCTAssertEqual(state.startedAt, startedAt)
    XCTAssertEqual(state.autoUnlockTargetDate, deadline)
    XCTAssertTrue(state.isLocked)
  }

  func testEndedLockCanBeginAgainWithoutRetainingTimingState() {
    let firstStart = Date(timeIntervalSinceReferenceDate: 1000)
    let secondStart = firstStart.addingTimeInterval(90)
    var state = LockRuntimeState()

    XCTAssertTrue(state.begin(settings: .default, at: firstStart))
    state.setAutoUnlockTargetDate(firstStart.addingTimeInterval(60))
    state.end()

    XCTAssertFalse(state.isLocked)
    XCTAssertNil(state.startedAt)
    XCTAssertNil(state.autoUnlockTargetDate)
    XCTAssertTrue(state.begin(settings: .default, at: secondStart))
    XCTAssertEqual(state.startedAt, secondStart)
  }
}
