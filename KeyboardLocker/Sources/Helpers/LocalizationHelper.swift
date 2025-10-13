import SwiftUI

// MARK: - Bundle Extensions for App Info

/// Extensions to Bundle for easy access to app information
extension Bundle {
  /// Get app version number from Info.plist
  var appVersion: String {
    infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
  }

  /// Get build version number from Info.plist
  var buildVersion: String {
    infoDictionary?["CFBundleVersion"] as? String ?? "1"
  }

  /// Human readable copyright information from Info.plist
  var copyright: String {
    object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
  }

  /// Formatted version string using localized format
  var localizedVersionString: String {
    let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    let versionFormat = LocalizationKey.aboutVersionFormat.localized
    return String(format: versionFormat, version)
  }
}

// MARK: - Localization Helper for .xcstrings

extension String {
  /// Returns a localized string for the given key using the modern .xcstrings format
  var localized: String {
    String(localized: String.LocalizationValue(self))
  }

  /// Returns a localized string with format arguments using .xcstrings
  func localized(_ arguments: CVarArg...) -> String {
    let localizedString = String(localized: String.LocalizationValue(self))
    return String(format: localizedString, arguments: arguments)
  }
}

// MARK: - Text Extension for Localization with .xcstrings

extension Text {
  /// Creates a Text view with localized string using .xcstrings
  init(localized key: String) {
    self.init(String(localized: String.LocalizationValue(key)))
  }
}

// MARK: - Localization Keys for .xcstrings

enum LocalizationKey {
  // App
  static let appTitle = "app.title"
  static let appMenuTitle = "app.menu.title"

  // Main Interface
  static let statusLocked = "status.locked"
  static let statusUnlocked = "status.unlocked"
  static let actionLock = "action.lock"
  static let actionUnlock = "action.unlock"
  static let actionQuit = "action.quit"

  // Quick Actions
  static let quickActions = "quick.actions"
  static let settingsTitle = "settings.title"
  static let settingsSubtitle = "settings.subtitle"
  static let aboutTitle = "about.title"
  static let aboutSubtitle = "about.subtitle"

  // Shortcuts
  static let shortcutHint = "shortcut.hint"

  // Settings
  static let settingsAutoLock = "settings.auto.lock"
  static let settingsAutoLockDescription = "settings.auto.lock.description"
  static let settingsNotifications = "settings.notifications"
  static let settingsShowNotifications = "settings.show.notifications"
  static let settingsNotificationsDescription = "settings.notifications.description"
  static let settingsKeyboard = "settings.keyboard"
  static let settingsKeyboardDescription = "settings.keyboard.description"
  static let settingsReset = "settings.reset"

  // Time durations and duration display
  static let timeMinutes = "time.minutes"
  static let timeActivityText = "time.activity.text"
  static let timeAutoLockDuration = "time.auto.lock.duration"
  static let autoLockStatus = "auto.lock.status"
  static let autoLockDisabled = "auto.lock.disabled"
  static let autoLockReadyToLock = "auto.lock.ready.to.lock"

  // Duration basic values (shared between time and duration contexts)
  static let durationNever = "duration.never"
  static let durationInfinite = "duration.infinite"

  // Duration display - parameterized forms
  static let durationMinutes = "duration.minutes" // "%d minute(s)"
  static let durationHours = "duration.hours" // "%d hour(s)"
  static let durationHoursMinutes = "duration.hours.minutes" // "%d hour(s) %d minute(s)"

  // Timed Lock
  static let timedLockTitle = "timed.lock.title"
  static let timedLockStart = "timed.lock.start"
  static let timedLockCustom = "timed.lock.custom"

  // About
  static let aboutVersionFormat = "about.version.format"
  static let aboutFeatures = "about.features"
  static let aboutFeatureLock = "about.feature.lock"
  static let aboutFeatureShortcut = "about.feature.shortcut"
  static let aboutFeatureNotifications = "about.feature.notifications"
  static let aboutFeatureAutoLock = "about.feature.auto.lock"
  static let aboutGitHub = "about.github"

  // Notifications
  static let notificationKeyboardLocked = "notification.keyboard.locked"
  static let notificationKeyboardUnlocked = "notification.keyboard.unlocked"
  static let notificationLockedMessage = "notification.locked.message"
  static let notificationUnlockedMessage = "notification.unlocked.message"
  static let notificationUrlCommand = "notification.url.command"
  static let notificationError = "notification.error"

  // Lock Duration
  static let lockDurationFormat = "lock.duration.format"
  static let timedLockRemaining = "timed.lock.remaining"

  // Permissions
  static let permissionRequired = "permission.required"
  static let permissionDescription = "permission.description"
  static let openSystemPreferences = "open.system.preferences"

  // URL Schemes - User facing messages only
  static let urlErrorInvalidScheme = "url.error.invalid.scheme"
  static let urlErrorMissingCommand = "url.error.missing.command"
  static let urlErrorUnknownCommand = "url.error.unknown.command"
  static let urlErrorManagerUnavailable = "url.error.manager.unavailable"

  static let urlResponseLockFailed = "url.response.lock.failed"
  static let urlResponseUnlockFailed = "url.response.unlock.failed"
}
