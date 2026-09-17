import Client
import Foundation
import Testing

@Suite(.serialized)
struct LockHistoryStatsTests {
  /// Fixed reference: 2023-11-15 12:00 UTC. Tests run against the GMT calendar so day
  /// boundaries never depend on the host timezone.
  private let now = Date(timeIntervalSince1970: 1_700_049_600)
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    return calendar
  }()

  @Test
  func emptyEntriesProduceEmptyStats() {
    let stats = LockHistoryStats.compute(entries: [], now: now, calendar: calendar)

    #expect(stats.isEmpty)
    #expect(stats.todayCount == 0)
    #expect(stats.reasonCounts.isEmpty)
  }

  @Test
  func entryBelongsToTheDayItEndedWithItsFullDuration() {
    // Started yesterday 23:50, ended today 00:10: counts today, all 20 minutes.
    let startOfToday = calendar.startOfDay(for: now)
    let stats = LockHistoryStats.compute(entries: [
      entry(
        start: startOfToday.addingTimeInterval(-600),
        end: startOfToday.addingTimeInterval(600),
        reason: .explicit
      ),
    ], now: now, calendar: calendar)

    #expect(stats.todayCount == 1)
    #expect(stats.todayDuration == 1200)
  }

  @Test
  func yesterdayCountsOnlyForTheWeek() {
    let startOfToday = calendar.startOfDay(for: now)
    let stats = LockHistoryStats.compute(entries: [
      entry(
        start: startOfToday.addingTimeInterval(-3600),
        end: startOfToday.addingTimeInterval(-1800),
        reason: .gesture
      ),
    ], now: now, calendar: calendar)

    #expect(stats.todayCount == 0)
    #expect(stats.weekCount == 1)
    #expect(stats.weekDuration == 1800)
    #expect(!stats.isEmpty)
  }

  @Test
  func entriesOlderThanSevenDaysCountOnlyForReasons() {
    let stats = LockHistoryStats.compute(entries: [
      entry(
        start: now.addingTimeInterval(-9 * 24 * 3600),
        end: now.addingTimeInterval(-8 * 24 * 3600),
        reason: .autoUnlock
      ),
    ], now: now, calendar: calendar)

    #expect(stats.todayCount == 0)
    #expect(stats.weekCount == 0)
    #expect(stats.reasonCounts == [.init(reason: .autoUnlock, count: 1)])
  }

  @Test
  func negativeDurationClampsToZero() {
    let stats = LockHistoryStats.compute(entries: [
      entry(start: now, end: now.addingTimeInterval(-50), reason: .explicit),
    ], now: now, calendar: calendar)

    #expect(stats.todayCount == 1)
    #expect(stats.todayDuration == 0)
  }

  @Test
  func reasonCountsSortByFrequencyThenName() {
    let stats = LockHistoryStats.compute(entries: [
      entry(start: now, end: now, reason: .autoUnlock),
      entry(start: now, end: now, reason: .gesture),
      entry(start: now, end: now, reason: .gesture),
      entry(start: now, end: now, reason: .explicit),
    ], now: now, calendar: calendar)

    #expect(stats.reasonCounts == [
      .init(reason: .gesture, count: 2),
      .init(reason: .autoUnlock, count: 1),
      .init(reason: .explicit, count: 1),
    ])
  }

  @Test
  func durationFormatting() {
    #expect(LockHistoryStats.formatDuration(0) == "0s")
    #expect(LockHistoryStats.formatDuration(45) == "45s")
    #expect(LockHistoryStats.formatDuration(60) == "1m")
    #expect(LockHistoryStats.formatDuration(200) == "3m 20s")
    #expect(LockHistoryStats.formatDuration(3600) == "1h 0m")
    #expect(LockHistoryStats.formatDuration(7320) == "2h 2m")
  }

  private func entry(start: Date, end: Date, reason: UnlockRecord.Reason) -> LockHistoryEntry {
    LockHistoryEntry(startedAt: start, endedAt: end, reason: reason)
  }
}
