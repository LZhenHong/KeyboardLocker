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

  func testNewFocusLockOwnsItsGeneration() throws {
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
    state.markCurrentLockAsFocusOwned()

    let generation = try XCTUnwrap(state.lockGeneration)
    XCTAssertEqual(state.focusOwnedGenerationForRelease, generation)
    XCTAssertTrue(state.matchesCurrentLockGeneration(generation))
  }

  func testFocusDuplicateDoesNotClaimExistingGeneralLock() throws {
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: startedAt
    )
    let generation = try XCTUnwrap(state.lockGeneration)

    XCTAssertEqual(
      state.handleDuplicateLockRequest(from: .focusFilter),
      .alreadyLocked
    )

    XCTAssertNil(state.focusOwnedGenerationForRelease)
    XCTAssertEqual(state.lockGeneration, generation)
    XCTAssertEqual(state.startedAt, startedAt)
  }

  func testRepeatedFocusEnablePreservesOwnedRuntimeState() {
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: .init(keyCode: 12, modifierFlags: [.maskCommand])
    )
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    let deadline = startedAt.addingTimeInterval(60)
    var state = LockRuntimeState()
    _ = state.begin(
      settings: settings,
      allowsControlCUnlock: false,
      at: startedAt
    )
    state.markCurrentLockAsFocusOwned()
    state.setAutoUnlockTargetDate(deadline)
    let originalState = state

    XCTAssertEqual(
      state.handleDuplicateLockRequest(from: .focusFilter),
      .alreadyLocked
    )

    XCTAssertEqual(state, originalState)
  }

  func testManualDesiredLockTakesOverFocusOwnershipWithoutChangingRuntimeState() throws {
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: .init(keyCode: 12, modifierFlags: [.maskCommand])
    )
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
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
    state.markCurrentLockAsFocusOwned()
    state.setAutoUnlockTargetDate(deadline)
    let generation = try XCTUnwrap(state.lockGeneration)

    XCTAssertEqual(
      state.handleDuplicateLockRequest(from: .general),
      .alreadyLocked
    )

    XCTAssertNil(state.focusOwnedLockGeneration)
    XCTAssertEqual(state.lockGeneration, generation)
    XCTAssertEqual(state.activeSettings, settings)
    XCTAssertFalse(state.allowsControlCUnlock)
    XCTAssertEqual(state.startedAt, startedAt)
    XCTAssertEqual(state.autoUnlockTargetDate, deadline)
    XCTAssertTrue(state.isLocked)
  }

  func testEndingFocusOwnedLockClearsOwnershipAndNextLockUsesNewGeneration() throws {
    let firstStart = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()

    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: firstStart
    )
    state.markCurrentLockAsFocusOwned()
    let firstGeneration = try XCTUnwrap(state.lockGeneration)

    XCTAssertEqual(state.focusOwnedLockGeneration, firstGeneration)

    state.end()

    XCTAssertNil(state.focusOwnedLockGeneration)
    XCTAssertNil(state.lockGeneration)

    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: firstStart.addingTimeInterval(1)
    )

    XCTAssertNotEqual(state.lockGeneration, firstGeneration)
    XCTAssertNil(state.focusOwnedLockGeneration)
    XCTAssertNil(state.focusOwnedGenerationForRelease)
    XCTAssertFalse(state.matchesCurrentLockGeneration(firstGeneration))
  }

  func testEarlyUnlockClearsFocusReleaseTarget() throws {
    var state = LockRuntimeState()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: Date(timeIntervalSinceReferenceDate: 1000)
    )
    state.markCurrentLockAsFocusOwned()
    let generation = try XCTUnwrap(state.focusOwnedGenerationForRelease)

    state.end()

    XCTAssertNil(state.focusOwnedGenerationForRelease)
    XCTAssertFalse(state.matchesCurrentLockGeneration(generation))
  }

  func testStaleFocusReleaseCannotMatchLaterLockGeneration() throws {
    var state = LockRuntimeState()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: Date(timeIntervalSinceReferenceDate: 1000)
    )
    state.markCurrentLockAsFocusOwned()
    let focusGeneration = try XCTUnwrap(state.focusOwnedGenerationForRelease)

    state.end()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: Date(timeIntervalSinceReferenceDate: 1001)
    )

    XCTAssertFalse(state.matchesCurrentLockGeneration(focusGeneration))
    XCTAssertNil(state.focusOwnedGenerationForRelease)
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
