import Core
import Foundation

/// Business logic helper for lock duration management and display
class LockDurationHelper {
  // MARK: - Preset Collections

  /// Preset durations for timed lock UI
  static let timedLockPresets: [CoreConfiguration.AutoLockDuration] = [
    .infinite,
    .minutes(1),
    .minutes(5),
    .minutes(15),
    .minutes(30),
    .minutes(60), // 1 hour
    .minutes(120), // 2 hours
    .minutes(240), // 4 hours
  ]

  /// Preset durations for auto-lock UI
  static let autoLockPresets: [CoreConfiguration.AutoLockDuration] = [
    .never,
    .minutes(15),
    .minutes(30),
    .minutes(60),
  ]

  /// Quick preset durations for timed lock
  static let quickTimedPresets: [CoreConfiguration.AutoLockDuration] = [
    .infinite,
    .minutes(1),
    .minutes(5),
    .minutes(15),
    .minutes(30),
  ]

  // MARK: - Display Logic

  /// Get localized display string for UI
  static func localizedDisplayString(for duration: CoreConfiguration.AutoLockDuration) -> String {
    switch duration {
    case .never:
      LocalizationKey.durationNever.localized
    case .infinite:
      LocalizationKey.durationInfinite.localized
    case let .minutes(minutes):
      formatMinutes(minutes)
    }
  }

  /// Get description text for duration settings
  static func localizedDescriptionString(for duration: CoreConfiguration.AutoLockDuration) -> String {
    switch duration {
    case .never:
      return LocalizationKey.durationNeverDescription.localized
    case .infinite:
      return LocalizationKey.durationInfiniteDescription.localized
    case let .minutes(minutes):
      if minutes < 60 {
        return LocalizationKey.durationMinutesDescription.localized(minutes)
      } else {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
          return LocalizationKey.durationHoursDescription.localized(hours)
        } else {
          return LocalizationKey.durationHoursMinutesDescription.localized(hours, remainingMinutes)
        }
      }
    }
  }

  // MARK: - Time Formatting Helpers

  private static func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 {
      return LocalizationKey.durationMinutes.localized(minutes)
    } else {
      let hours = minutes / 60
      let remainingMinutes = minutes % 60
      if remainingMinutes == 0 {
        return LocalizationKey.durationHours.localized(hours)
      } else {
        return LocalizationKey.durationHoursMinutes.localized(hours, remainingMinutes)
      }
    }
  }

  // MARK: - Factory Methods

  /// Create duration from seconds with smart conversion
  static func durationFromSeconds(_ seconds: TimeInterval) -> CoreConfiguration.AutoLockDuration {
    let totalSeconds = Int(seconds)

    if totalSeconds == 0 {
      return .infinite
    } else if totalSeconds < 60 {
      // For very short durations, round up to 1 minute
      return .minutes(1)
    } else {
      let minutes = totalSeconds / 60
      return .minutes(minutes)
    }
  }

  /// Create duration from total seconds (exact)
  static func durationFromSecondsExact(_ seconds: TimeInterval)
    -> CoreConfiguration.AutoLockDuration
  {
    let totalSeconds = Int(seconds)

    if totalSeconds == 0 {
      return .infinite
    } else {
      let minutes = max(1, totalSeconds / 60) // Minimum 1 minute
      return .minutes(minutes)
    }
  }

  // MARK: - Validation

  /// Check if this duration is valid for timed lock
  static func isValidForTimedLock(_ duration: CoreConfiguration.AutoLockDuration) -> Bool {
    switch duration {
    case .never:
      false // Never is not valid for timed lock
    case .infinite, .minutes:
      true
    }
  }

  /// Check if this duration is valid for auto-lock
  static func isValidForAutoLock(_ duration: CoreConfiguration.AutoLockDuration) -> Bool {
    switch duration {
    case .never, .minutes:
      true
    case .infinite:
      false // Infinite is not valid for auto-lock
    }
  }

  // MARK: - Comparison Helpers

  /// Get sort order for duration comparison
  static func sortOrder(for duration: CoreConfiguration.AutoLockDuration) -> Int {
    switch duration {
    case .never:
      0
    case .infinite:
      Int.max
    case let .minutes(minutes):
      minutes
    }
  }
}
