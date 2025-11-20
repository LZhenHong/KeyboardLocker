import Foundation

@objc(KeyboardLockerServiceProtocol)
public protocol KeyboardLockerServiceProtocol {
  // MARK: - Keyboard Locking Methods

  func lockKeyboard(reply: @escaping (Error?) -> Void)
  func unlockKeyboard(reply: @escaping (Error?) -> Void)
  func status(reply: @escaping (Bool, Error?) -> Void)

  // MARK: - Accessibility Methods

  func accessibilityStatus(reply: @escaping (Bool) -> Void)
}
