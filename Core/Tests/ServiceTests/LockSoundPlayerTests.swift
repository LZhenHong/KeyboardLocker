import Common
import Foundation
@testable import Service
import Testing

@MainActor
@Suite(.serialized)
final class LockSoundPlayerTests {
  @Test
  func lockAndUnlockEdgesPlaySounds() {
    let sounds = RecordingSounds()
    var isLocked = false
    let player = LockSoundPlayer(sounds: sounds) {
      Self.makeSnapshot(isLocked: isLocked)
    }

    isLocked = true
    player.lockStateDidChange()
    #expect(sounds.events == [.lock])

    isLocked = false
    player.lockStateDidChange()
    #expect(sounds.events == [.lock, .unlock])
  }

  @Test
  func repeatedPublishOfSameStateStaysSilent() {
    let sounds = RecordingSounds()
    var isLocked = false
    let player = LockSoundPlayer(sounds: sounds) {
      Self.makeSnapshot(isLocked: isLocked)
    }

    player.lockStateDidChange()
    player.lockStateDidChange()
    #expect(sounds.events.isEmpty)

    isLocked = true
    player.lockStateDidChange()
    player.lockStateDidChange()
    #expect(sounds.events == [.lock])
  }

  @Test
  func disabledSoundsStaySilentOnBothEdges() {
    let sounds = RecordingSounds()
    var isLocked = false
    let player = LockSoundPlayer(sounds: sounds) {
      Self.makeSnapshot(isLocked: isLocked, soundEffectsEnabled: false)
    }

    isLocked = true
    player.lockStateDidChange()
    isLocked = false
    player.lockStateDidChange()
    #expect(sounds.events.isEmpty)
  }

  @Test
  func playerStartsFromCurrentStateWithoutPlaying() {
    let sounds = RecordingSounds()
    // An Agent that bootstraps while already locked must not replay the lock cue.
    _ = LockSoundPlayer(sounds: sounds) {
      Self.makeSnapshot(isLocked: true)
    }
    #expect(sounds.events.isEmpty)
  }

  private static func makeSnapshot(
    isLocked: Bool,
    soundEffectsEnabled: Bool = true
  ) -> LockStatusSnapshot {
    LockStatusSnapshot(
      capturedAt: Date(timeIntervalSinceReferenceDate: 0),
      isLocked: isLocked,
      startedAt: isLocked ? Date(timeIntervalSinceReferenceDate: 0) : nil,
      autoUnlockTargetDate: nil,
      settings: KeyboardLockerSettings(
        autoUnlockPolicy: .disabled,
        unlockHotkey: .init(keyCode: 4, modifierFlags: .maskShift),
        soundEffectsEnabled: soundEffectsEnabled
      ),
      lastUnlock: nil
    )
  }
}

@MainActor
private final class RecordingSounds: LockSoundPlaying {
  enum Event: Equatable {
    case lock
    case unlock
  }

  private(set) var events: [Event] = []

  func playLockSound() {
    events.append(.lock)
  }

  func playUnlockSound() {
    events.append(.unlock)
  }
}
