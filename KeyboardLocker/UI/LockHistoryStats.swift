import Client
import Foundation

/// Presentation derivation over the Agent's authoritative lock history.
///
/// Pure and injectable (now, calendar) so the day-boundary rules stay unit-testable. The Agent
/// owns the records; this only aggregates them, the same rule the menu-bar countdown follows
/// for the snapshot's deadline.
struct LockHistoryStats: Equatable {
  struct ReasonCount: Equatable {
    var reason: UnlockRecord.Reason
    var count: Int
  }

  var todayCount: Int
  var todayDuration: TimeInterval
  var weekCount: Int
  var weekDuration: TimeInterval
  /// Unlock-method histogram over every retained entry, most frequent first.
  var reasonCounts: [ReasonCount]

  var isEmpty: Bool {
    todayCount == 0 && weekCount == 0 && reasonCounts.isEmpty
  }

  /// An entry belongs to the day it *ended*: a lock spanning midnight counts toward the day
  /// the keyboard came back, with its full duration. "Week" is a rolling 7-day window, not a
  /// calendar week. Durations clamp at zero — a backwards clock reading must not subtract
  /// time from the user's stats.
  static func compute(
    entries: [LockHistoryEntry],
    now: Date,
    calendar: Calendar = .current
  ) -> LockHistoryStats {
    let todayStart = calendar.startOfDay(for: now)
    let weekStart = now.addingTimeInterval(-7 * 24 * 3600)

    var todayCount = 0
    var todayDuration: TimeInterval = 0
    var weekCount = 0
    var weekDuration: TimeInterval = 0
    var countsByReason: [UnlockRecord.Reason: Int] = [:]

    for entry in entries {
      let duration = max(0, entry.duration)
      countsByReason[entry.reason, default: 0] += 1
      if entry.endedAt >= todayStart {
        todayCount += 1
        todayDuration += duration
      }
      if entry.endedAt >= weekStart {
        weekCount += 1
        weekDuration += duration
      }
    }

    let reasonCounts = countsByReason
      .map { ReasonCount(reason: $0.key, count: $0.value) }
      .sorted {
        $0.count != $1.count
          ? $0.count > $1.count
          : $0.reason.displayName < $1.reason.displayName
      }

    return LockHistoryStats(
      todayCount: todayCount,
      todayDuration: todayDuration,
      weekCount: weekCount,
      weekDuration: weekDuration,
      reasonCounts: reasonCounts
    )
  }

  /// Compact duration copy: "45s", "3m 20s", "1h 12m".
  static func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(duration.rounded())
    if totalSeconds < 60 {
      return "\(totalSeconds)s"
    }
    let minutes = totalSeconds / 60
    if minutes < 60 {
      let seconds = totalSeconds % 60
      return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }
    return "\(minutes / 60)h \(minutes % 60)m"
  }
}
