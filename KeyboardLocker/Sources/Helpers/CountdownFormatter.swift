import Core
import Foundation

enum CountdownFormatter {
  /// Format remaining time as countdown string
  static func countdownString(from timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(timeInterval)

    if totalSeconds <= 0 {
      return "00:00"
    }

    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }

  /// Format remaining time as human readable string
  static func humanReadableCountdown(from timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(timeInterval)

    if totalSeconds <= 0 {
      return LocalizationKey.countdownFinished.localized
    }

    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return LocalizationKey.countdownHoursFormat.localized(hours, minutes, seconds)
    } else if minutes > 0 {
      return LocalizationKey.countdownMinutesFormat.localized(minutes, seconds)
    } else {
      return LocalizationKey.countdownSecondsFormat.localized(seconds)
    }
  }
}
