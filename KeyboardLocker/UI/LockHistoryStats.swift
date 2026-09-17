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

  /// One unlock method's locked time within a day, kept in the same rank order as
  /// `reasonCounts` so day bars and the overall share line can share one color mapping.
  struct MethodDuration: Equatable {
    var reason: UnlockRecord.Reason
    var duration: TimeInterval
  }

  /// One calendar day's totals, the bar chart's data source.
  struct DayActivity: Equatable {
    var dayStart: Date
    var count: Int
    var duration: TimeInterval
    /// Locked time split by unlock method, empty on days without entries.
    var durationByMethod: [MethodDuration]
  }

  var todayCount: Int
  var todayDuration: TimeInterval
  var weekCount: Int
  var weekDuration: TimeInterval
  /// Midnight of today in the given calendar, the chart's highlight anchor.
  var todayStart: Date
  /// The current calendar week, Sunday through Saturday; days after today stay zero-filled so
  /// the chart always shows the same seven slots.
  var dailyActivity: [DayActivity]
  /// Unlock-method histogram over every retained entry, most frequent first.
  var reasonCounts: [ReasonCount]

  var isEmpty: Bool {
    todayCount == 0 && weekCount == 0 && reasonCounts.isEmpty
  }

  /// An entry belongs to the day it *ended*: a lock spanning midnight counts toward the day
  /// the keyboard came back, with its full duration. "Week" is exactly the seven `dailyActivity`
  /// buckets — chart and totals share one definition so the page cannot disagree with itself.
  /// Durations clamp at zero — a backwards clock reading must not subtract time from the
  /// user's stats.
  static func compute(
    entries: [LockHistoryEntry],
    now: Date,
    calendar: Calendar = .current
  ) -> LockHistoryStats {
    let todayStart = calendar.startOfDay(for: now)
    // The chart's columns read Sunday through Saturday as requested, so the week is anchored
    // to weekday 1 (Sunday in the Gregorian calendar) rather than the locale's first weekday.
    // `byAdding` walks DST transitions instead of assuming 86,400-second days.
    let daysSinceSunday = calendar.component(.weekday, from: todayStart) - 1
    let weekStart = calendar.date(byAdding: .day, value: -daysSinceSunday, to: todayStart)!
    let dayStarts = (0 ... 6).map {
      calendar.date(byAdding: .day, value: $0, to: weekStart)!
    }
    var dailyActivity = dayStarts.map {
      DayActivity(dayStart: $0, count: 0, duration: 0, durationByMethod: [])
    }
    var durationByReasonPerDay = dayStarts.map { _ in [UnlockRecord.Reason: TimeInterval]() }
    var countsByReason: [UnlockRecord.Reason: Int] = [:]

    for entry in entries {
      let duration = max(0, entry.duration)
      countsByReason[entry.reason, default: 0] += 1
      let dayStart = calendar.startOfDay(for: entry.endedAt)
      if let index = dayStarts.firstIndex(of: dayStart) {
        dailyActivity[index].count += 1
        dailyActivity[index].duration += duration
        durationByReasonPerDay[index][entry.reason, default: 0] += duration
      }
    }

    let today = dailyActivity[daysSinceSunday]
    let todayCount = today.count
    let todayDuration = today.duration
    let weekCount = dailyActivity.reduce(0) { $0 + $1.count }
    let weekDuration = dailyActivity.reduce(0) { $0 + $1.duration }

    let reasonCounts = countsByReason
      .map { ReasonCount(reason: $0.key, count: $0.value) }
      .sorted {
        $0.count != $1.count
          ? $0.count > $1.count
          : $0.reason.displayName < $1.reason.displayName
      }

    // Per-day segments in the overall rank order, so a day bar's colors always mean the same
    // methods as the share line's, no matter which unlock happened to end first that day.
    let rank = Dictionary(
      uniqueKeysWithValues: reasonCounts.enumerated().map { ($0.element.reason, $0.offset) }
    )
    for index in dailyActivity.indices {
      dailyActivity[index].durationByMethod = durationByReasonPerDay[index]
        .map { MethodDuration(reason: $0.key, duration: $0.value) }
        .sorted { (rank[$0.reason] ?? .max) < (rank[$1.reason] ?? .max) }
    }

    return LockHistoryStats(
      todayCount: todayCount,
      todayDuration: todayDuration,
      weekCount: weekCount,
      weekDuration: weekDuration,
      todayStart: todayStart,
      dailyActivity: dailyActivity,
      reasonCounts: reasonCounts
    )
  }

  /// Plural-aware count copy: "1 lock", "12 locks".
  static func formatLockCount(_ count: Int) -> String {
    count == 1 ? "1 lock" : "\(count) locks"
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
