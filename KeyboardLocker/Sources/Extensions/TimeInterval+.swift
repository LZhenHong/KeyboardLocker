import Foundation

public extension TimeInterval {
  var formattedCountdown: String {
    let totalSeconds = Int(self)
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
}
