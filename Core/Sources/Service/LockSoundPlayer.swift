import AppKit
import Common
import Foundation

/// Sound playback surface used by `LockSoundPlayer`. The live implementation wraps `NSSound`;
/// tests drive a recording fake.
@MainActor
protocol LockSoundPlaying {
  func playLockSound()
  func playUnlockSound()
}

/// Plays a short sound on lock/unlock transitions from inside the Agent process.
///
/// Like the "Keyboard Locked" notification, the audible cue must outlive any wrapper, so it
/// hooks the same engine state-change slot the notifier uses and reads the same authoritative
/// snapshot. It is presentation-only: the active settings' `soundEffectsEnabled` gates each
/// edge, and a missing sound degrades to silence rather than an error.
@MainActor
final class LockSoundPlayer {
  private let sounds: any LockSoundPlaying
  private let snapshot: @MainActor () -> LockStatusSnapshot
  private var wasLocked: Bool

  init(
    sounds: any LockSoundPlaying,
    snapshot: @escaping @MainActor () -> LockStatusSnapshot
  ) {
    self.sounds = sounds
    self.snapshot = snapshot
    wasLocked = snapshot().isLocked
  }

  /// Engine state-change hook, invoked after the mutation completed so the snapshot read here
  /// already describes the new state. Only edges play; the repeated publish of an unchanged
  /// state stays silent.
  func lockStateDidChange() {
    let current = snapshot()
    defer { wasLocked = current.isLocked }
    guard current.isLocked != wasLocked,
          current.settings.soundEffectsEnabled
    else {
      return
    }
    if current.isLocked {
      sounds.playLockSound()
    } else {
      sounds.playUnlockSound()
    }
  }
}

/// Production `LockSoundPlaying` backed by system alert sounds.
@MainActor
final class LiveLockSoundService: LockSoundPlaying {
  private static let lockSoundName = NSSound.Name("Tink")
  private static let unlockSoundName = NSSound.Name("Glass")
  /// Kept under full volume: the cue confirms a transition, it must not startle someone whose
  /// hands are off the keyboard while it is being cleaned.
  private static let volume: Float = 0.5

  func playLockSound() {
    play(named: Self.lockSoundName)
  }

  func playUnlockSound() {
    play(named: Self.unlockSoundName)
  }

  private func play(named name: NSSound.Name) {
    guard let sound = NSSound(named: name) else {
      return
    }
    sound.volume = Self.volume
    sound.play()
  }
}
