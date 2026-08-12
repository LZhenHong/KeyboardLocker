import Foundation

/// App-owned presentation preference. This does not mirror Agent settings or lock state.
struct SafetyCheckExperienceStore {
  private static let completionKey = "keyboardlocker.safety-check.completed"

  private let completionKey: String
  private let userDefaults: UserDefaults

  init(
    userDefaults: UserDefaults = .standard,
    completionKey: String = Self.completionKey
  ) {
    self.userDefaults = userDefaults
    self.completionKey = completionKey
  }

  var hasCompletedSafetyCheck: Bool {
    userDefaults.bool(forKey: completionKey)
  }

  func markCompleted() {
    userDefaults.set(true, forKey: completionKey)
  }
}
