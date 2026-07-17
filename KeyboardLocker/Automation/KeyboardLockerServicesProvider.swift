import AppKit

final nonisolated class KeyboardLockerServicesProvider: NSObject, @unchecked Sendable {
  private let submit: @Sendable (ExternalAutomationAction) -> Void

  init(submit: @escaping @Sendable (ExternalAutomationAction) -> Void) {
    self.submit = submit
  }

  @objc(lockKeyboard:userData:error:)
  nonisolated func lockKeyboard(
    _: NSPasteboard,
    userData _: String?,
    error _: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    submit(.lock)
  }

  @objc(unlockKeyboard:userData:error:)
  nonisolated func unlockKeyboard(
    _: NSPasteboard,
    userData _: String?,
    error _: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    submit(.unlock)
  }

  @objc(showKeyboardLockStatus:userData:error:)
  nonisolated func showKeyboardLockStatus(
    _: NSPasteboard,
    userData _: String?,
    error _: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    submit(.status)
  }
}
