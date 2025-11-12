import Core

/// Business logic helper for lock duration management and display
extension CoreConfiguration.Duration {
  // MARK: - Preset Collections

  /// Preset durations for auto-lock UI
  static let autoLockPresets: [Self] = [
    .never,
    .minutes(15),
    .minutes(30),
    .minutes(60),
  ]

  // MARK: - Display Logic

  /// Get localized display string for UI
  var localized: String {
    switch self {
    case .never:
      LocalizationKey.durationNever.localized
    case .infinite:
      LocalizationKey.durationInfinite.localized
    case let .minutes(minutes):
      minutes.formatted
    }
  }
}

private extension Int {
  var formatted: String {
    if self < 60 {
      return LocalizationKey.durationMinutes.localized(self)
    } else {
      let hours = self / 60
      let remainingMinutes = self % 60
      if remainingMinutes == 0 {
        return LocalizationKey.durationHours.localized(hours)
      } else {
        return LocalizationKey.durationHoursMinutes.localized(hours, remainingMinutes)
      }
    }
  }
}
