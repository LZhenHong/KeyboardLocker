import Common
import Foundation
@testable import Service
import Testing

@Suite(.serialized)
struct LockRuntimeStateTests {
  @Test
  func interactiveDuplicateDoesNotEnableControlCForExistingLock() {
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()

    #expect(
      state.begin(
        settings: .default,
        allowsControlCUnlock: false,
        at: startedAt
      ) == .acquired
    )
    #expect(
      state.begin(
        settings: .default,
        allowsControlCUnlock: true,
        at: startedAt.addingTimeInterval(1)
      ) == .alreadyLocked
    )

    #expect(!state.allowsControlCUnlock)
    #expect(state.startedAt == startedAt)
  }

  @Test
  func duplicateBeginPreservesOriginalRuntimeStateAndDeadline() {
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

    #expect(
      state.begin(
        settings: originalSettings,
        allowsControlCUnlock: true,
        at: startedAt
      ) == .acquired
    )
    state.setAutoUnlockTargetDate(deadline)

    #expect(
      state.begin(
        settings: replacementSettings,
        allowsControlCUnlock: false,
        at: startedAt.addingTimeInterval(10)
      ) == .alreadyLocked
    )
    #expect(state.activeSettings == originalSettings)
    #expect(state.allowsControlCUnlock)
    #expect(state.startedAt == startedAt)
    #expect(state.autoUnlockTargetDate == deadline)
    #expect(state.isLocked)
  }

  @Test
  func endedLockCanBeginAgainWithoutRetainingTimingState() {
    let firstStart = Date(timeIntervalSinceReferenceDate: 1000)
    let secondStart = firstStart.addingTimeInterval(90)
    var state = LockRuntimeState()

    #expect(
      state.begin(
        settings: .default,
        allowsControlCUnlock: true,
        at: firstStart
      ) == .acquired
    )
    state.setAutoUnlockTargetDate(firstStart.addingTimeInterval(60))
    state.end()

    #expect(!state.allowsControlCUnlock)
    #expect(!state.isLocked)
    #expect(state.startedAt == nil)
    #expect(state.autoUnlockTargetDate == nil)
    #expect(
      state.begin(
        settings: .default,
        allowsControlCUnlock: false,
        at: secondStart
      ) == .acquired
    )
    #expect(!state.allowsControlCUnlock)
    #expect(state.startedAt == secondStart)
  }

  @Test
  func newFocusLockOwnsItsGeneration() throws {
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()

    #expect(
      state.begin(
        settings: .default,
        allowsControlCUnlock: false,
        at: startedAt
      ) == .acquired
    )
    state.markCurrentLockAsFocusOwned()

    let generation = try #require(state.lockGeneration)
    #expect(state.focusOwnedGenerationForRelease == generation)
    #expect(state.matchesCurrentLockGeneration(generation))
  }

  @Test
  func focusDuplicateDoesNotClaimExistingGeneralLock() throws {
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: startedAt
    )
    let generation = try #require(state.lockGeneration)

    #expect(
      state.handleDuplicateLockRequest(from: .focusFilter) == .alreadyLocked
    )

    #expect(state.focusOwnedGenerationForRelease == nil)
    #expect(state.lockGeneration == generation)
    #expect(state.startedAt == startedAt)
  }

  @Test
  func repeatedFocusEnablePreservesOwnedRuntimeState() {
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

    #expect(
      state.handleDuplicateLockRequest(from: .focusFilter) == .alreadyLocked
    )

    #expect(state == originalState)
  }

  @Test
  func manualDesiredLockTakesOverFocusOwnershipWithoutChangingRuntimeState() throws {
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: .init(keyCode: 12, modifierFlags: [.maskCommand])
    )
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    let deadline = startedAt.addingTimeInterval(60)
    var state = LockRuntimeState()

    #expect(
      state.begin(
        settings: settings,
        allowsControlCUnlock: false,
        at: startedAt
      ) == .acquired
    )
    state.markCurrentLockAsFocusOwned()
    state.setAutoUnlockTargetDate(deadline)
    let generation = try #require(state.lockGeneration)

    #expect(
      state.handleDuplicateLockRequest(from: .general) == .alreadyLocked
    )

    #expect(state.focusOwnedLockGeneration == nil)
    #expect(state.lockGeneration == generation)
    #expect(state.activeSettings == settings)
    #expect(!state.allowsControlCUnlock)
    #expect(state.startedAt == startedAt)
    #expect(state.autoUnlockTargetDate == deadline)
    #expect(state.isLocked)
  }

  @Test
  func endingFocusOwnedLockClearsOwnershipAndNextLockUsesNewGeneration() throws {
    let firstStart = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()

    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: firstStart
    )
    state.markCurrentLockAsFocusOwned()
    let firstGeneration = try #require(state.lockGeneration)

    #expect(state.focusOwnedLockGeneration == firstGeneration)

    state.end()

    #expect(state.focusOwnedLockGeneration == nil)
    #expect(state.lockGeneration == nil)

    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: firstStart.addingTimeInterval(1)
    )

    #expect(state.lockGeneration != firstGeneration)
    #expect(state.focusOwnedLockGeneration == nil)
    #expect(state.focusOwnedGenerationForRelease == nil)
    #expect(!state.matchesCurrentLockGeneration(firstGeneration))
  }

  @Test
  func earlyUnlockClearsFocusReleaseTarget() throws {
    var state = LockRuntimeState()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: Date(timeIntervalSinceReferenceDate: 1000)
    )
    state.markCurrentLockAsFocusOwned()
    let generation = try #require(state.focusOwnedGenerationForRelease)

    state.end()

    #expect(state.focusOwnedGenerationForRelease == nil)
    #expect(!state.matchesCurrentLockGeneration(generation))
  }

  @Test
  func staleFocusReleaseCannotMatchLaterLockGeneration() throws {
    var state = LockRuntimeState()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: Date(timeIntervalSinceReferenceDate: 1000)
    )
    state.markCurrentLockAsFocusOwned()
    let focusGeneration = try #require(state.focusOwnedGenerationForRelease)

    state.end()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: Date(timeIntervalSinceReferenceDate: 1001)
    )

    #expect(!state.matchesCurrentLockGeneration(focusGeneration))
    #expect(state.focusOwnedGenerationForRelease == nil)
  }

  @Test
  func snapshotCapturesOneCoherentRuntimeState() {
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: .init(keyCode: 12, modifierFlags: [.maskCommand])
    )
    let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
    let capturedAt = startedAt.addingTimeInterval(10)
    let deadline = startedAt.addingTimeInterval(60)
    var state = LockRuntimeState()

    #expect(
      state.begin(
        settings: settings,
        allowsControlCUnlock: false,
        at: startedAt
      ) == .acquired
    )
    state.setAutoUnlockTargetDate(deadline)

    #expect(
      state.statusSnapshot(capturedAt: capturedAt) == LockStatusSnapshot(
        capturedAt: capturedAt,
        isLocked: true,
        startedAt: startedAt,
        autoUnlockTargetDate: deadline,
        settings: settings
      )
    )
  }

  @Test
  func snapshotClearsRuntimeDatesAfterUnlock() {
    let capturedAt = Date(timeIntervalSinceReferenceDate: 1000)
    var state = LockRuntimeState()
    _ = state.begin(
      settings: .default,
      allowsControlCUnlock: false,
      at: capturedAt.addingTimeInterval(-10)
    )
    state.setAutoUnlockTargetDate(capturedAt.addingTimeInterval(50))
    state.end()

    #expect(
      state.statusSnapshot(capturedAt: capturedAt) == LockStatusSnapshot(
        capturedAt: capturedAt,
        isLocked: false,
        startedAt: nil,
        autoUnlockTargetDate: nil,
        settings: .default
      )
    )
  }
}
