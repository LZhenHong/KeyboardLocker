import Common
import Foundation
@testable import Service
import XCTest

final class LockRuntimeStateTests: XCTestCase {
  func testInteractiveDuplicateDoesNotEnableControlCForExistingLock() {
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()

    XCTAssertEqual(
      state.begin(
        settings: .default,
        allowsControlCUnlock: false,
        at: startedAt
      ),
      .acquired
    )
    XCTAssertEqual(
      state.begin(
        settings: .default,
        allowsControlCUnlock: true,
        at: startedAt.addingTimeInterval(1)
      ),
      .alreadyLocked
    )

    XCTAssertFalse(state.allowsControlCUnlock)
    XCTAssertEqual(state.startedAt, startedAt)
  }

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

    XCTAssertEqual(
      state.begin(
        settings: originalSettings,
        allowsControlCUnlock: true,
        at: startedAt
      ),
      .acquired
    )
    state.setAutoUnlockTargetDate(deadline)

    XCTAssertEqual(
      state.begin(
        settings: replacementSettings,
        allowsControlCUnlock: false,
        at: startedAt.addingTimeInterval(10)
      ),
      .alreadyLocked
    )
    XCTAssertEqual(state.activeSettings, originalSettings)
    XCTAssertTrue(state.allowsControlCUnlock)
    XCTAssertEqual(state.startedAt, startedAt)
    XCTAssertEqual(state.autoUnlockTargetDate, deadline)
    XCTAssertTrue(state.isLocked)
  }

  func testEndedLockCanBeginAgainWithoutRetainingTimingState() {
    let firstStart = Date(timeIntervalSinceReferenceDate: 1000)
    let secondStart = firstStart.addingTimeInterval(90)
    var state = LockRuntimeState()

    XCTAssertEqual(
      state.begin(
        settings: .default,
        allowsControlCUnlock: true,
        at: firstStart
      ),
      .acquired
    )
    state.setAutoUnlockTargetDate(firstStart.addingTimeInterval(60))
    state.end()

    XCTAssertFalse(state.allowsControlCUnlock)
    XCTAssertFalse(state.isLocked)
    XCTAssertNil(state.startedAt)
    XCTAssertNil(state.autoUnlockTargetDate)
    XCTAssertEqual(
      state.begin(
        settings: .default,
        allowsControlCUnlock: false,
        at: secondStart
      ),
      .acquired
    )
    XCTAssertFalse(state.allowsControlCUnlock)
    XCTAssertEqual(state.startedAt, secondStart)
  }

  func testSnapshotCapturesOneCoherentRuntimeState() {
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: .init(keyCode: 12, modifierFlags: [.maskCommand])
    )
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    let capturedAt = startedAt.addingTimeInterval(10)
    let deadline = startedAt.addingTimeInterval(60)
    var state = LockRuntimeState()

    XCTAssertEqual(
      state.begin(
        settings: settings,
        allowsControlCUnlock: false,
        at: startedAt
      ),
      .acquired
    )
    state.setAutoUnlockTargetDate(deadline)

    XCTAssertEqual(
      state.statusSnapshot(capturedAt: capturedAt),
      LockStatusSnapshot(
        capturedAt: capturedAt,
        isLocked: true,
        startedAt: startedAt,
        autoUnlockTargetDate: deadline,
        settings: settings
      )
    )
  }

  func testSnapshotClearsRuntimeDatesAfterUnlock() {
    let capturedAt = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: capturedAt.addingTimeInterval(-10)
    )
    state.setAutoUnlockTargetDate(capturedAt.addingTimeInterval(50))
    state.end()

    XCTAssertEqual(
      state.statusSnapshot(capturedAt: capturedAt),
      LockStatusSnapshot(
        capturedAt: capturedAt,
        isLocked: false,
        startedAt: nil,
        autoUnlockTargetDate: nil,
        settings: .default
      )
    )
  }
}
