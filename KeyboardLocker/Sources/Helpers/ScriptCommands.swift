import AppKit
import Core
import Foundation

// MARK: - AppleScript Command Handlers

/// AppleScript command: lock keyboard
/// Usage: tell application "KeyboardLocker" to lock
/// Uses Core package directly for immediate availability at app launch
@objc(LockKeyboardCommand)
final class LockKeyboardCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    let core = KeyboardLockCore.shared

    do {
      try core.lockKeyboard()
      print("🍎 AppleScript: lock keyboard")
      return core.isLocked
    } catch {
      scriptErrorNumber = errOSAGeneralError
      scriptErrorString = "Failed to lock keyboard: \(error.localizedDescription)"
      return false
    }
  }
}

/// AppleScript command: unlock keyboard
/// Usage: tell application "KeyboardLocker" to unlock
/// Uses Core package directly for immediate availability at app launch
@objc(UnlockKeyboardCommand)
final class UnlockKeyboardCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    let core = KeyboardLockCore.shared

    core.unlockKeyboard()
    print("🍎 AppleScript: unlock keyboard")
    return !core.isLocked
  }
}

/// AppleScript command: toggle keyboard lock
/// Usage: tell application "KeyboardLocker" to toggle
/// Uses Core package directly for immediate availability at app launch
@objc(ToggleKeyboardLockCommand)
final class ToggleKeyboardLockCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    let core = KeyboardLockCore.shared

    core.toggleLock()
    print("🍎 AppleScript: toggle keyboard lock -> \(core.isLocked ? "locked" : "unlocked")")
    return core.isLocked
  }
}
