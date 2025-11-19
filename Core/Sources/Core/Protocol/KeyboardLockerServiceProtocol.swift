import Foundation

@objc(KeyboardLockerServiceProtocol)
public protocol KeyboardLockerServiceProtocol {
  func lockKeyboard(reply: @escaping (Error?) -> Void)
  func unlockKeyboard(reply: @escaping (Error?) -> Void)
  func status(reply: @escaping (Bool, Error?) -> Void)
}
