import Client
import Foundation
import Testing

@Suite(.serialized)
struct LockHistoryStatsTests {
  /// Fixed reference: 2023-11-15 12:00 UTC, a Wednesday — its calendar week runs Sunday
  /// 11-12 (index 0) through Saturday 11-18 (index 6), today at index 3. Tests run against
  /// the GMT calendar so day boundaries never depend on the host timezone.
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
  func dailyActivitySpansTheCurrentCalendarWeekSundayToSaturday() {
    let stats = LockHistoryStats.compute(entries: [], now: now, calendar: calendar)

    let startOfToday = calendar.startOfDay(for: now)
    #expect(stats.dailyActivity.count == 7)
    #expect(stats.dailyActivity.first?.dayStart == calendar.date(byAdding: .day, value: -3, to: startOfToday))
    #expect(stats.dailyActivity.last?.dayStart == calendar.date(byAdding: .day, value: 3, to: startOfToday))
    #expect(stats.dailyActivity.first.map { calendar.component(.weekday, from: $0.dayStart) } == 1)
    #expect(stats.dailyActivity.last.map { calendar.component(.weekday, from: $0.dayStart) } == 7)
    #expect(stats.todayStart == startOfToday)
    #expect(stats.dailyActivity.allSatisfy { $0.count == 0 && $0.duration == 0 })
  }

  @Test
  func dailyActivityBucketsEntriesByTheDayTheyEnded() {
    let startOfToday = calendar.startOfDay(for: now)
    let stats = LockHistoryStats.compute(entries: [
      entry(
        start: startOfToday.addingTimeInterval(-7200),
        end: startOfToday.addingTimeInterval(-3600),
        reason: .explicit
      ),
      entry(
        start: startOfToday.addingTimeInterval(-5400),
        end: startOfToday.addingTimeInterval(-4500),
        reason: .phrase
      ),
      // Started yesterday 23:50, ended today 00:10: today's bucket, all 20 minutes.
      entry(
        start: startOfToday.addingTimeInterval(-600),
        end: startOfToday.addingTimeInterval(600),
        reason: .gesture
      ),
    ], now: now, calendar: calendar)

    #expect(stats.dailyActivity[2].count == 2)
    #expect(stats.dailyActivity[2].duration == 4500)
    #expect(stats.dailyActivity[2].durationByMethod == [
      .init(reason: .explicit, duration: 3600),
      .init(reason: .phrase, duration: 900),
    ])
    #expect(stats.dailyActivity[3].count == 1)
    #expect(stats.dailyActivity[3].duration == 1200)
    #expect(stats.dailyActivity[3].durationByMethod == [
      .init(reason: .gesture, duration: 1200),
    ])
    // Thursday through Saturday of this week haven't happened yet.
    #expect(stats.dailyActivity[4...].allSatisfy { $0.count == 0 && $0.duration == 0 })
  }

  @Test
  func daySegmentsFollowTheOverallRankNotEntryOrder() {
    let startOfToday = calendar.startOfDay(for: now)
    let stats = LockHistoryStats.compute(entries: [
      // Phrase ends first, but Manual wins the overall count, so it must lead the day bar.
      entry(start: startOfToday, end: startOfToday.addingTimeInterval(600), reason: .phrase),
      entry(
        start: startOfToday.addingTimeInterval(700),
        end: startOfToday.addingTimeInterval(1300),
        reason: .explicit
      ),
      entry(
        start: startOfToday.addingTimeInterval(1400),
        end: startOfToday.addingTimeInterval(2000),
        reason: .explicit
      ),
    ], now: now, calendar: calendar)

    #expect(stats.dailyActivity[3].durationByMethod == [
      .init(reason: .explicit, duration: 1200),
      .init(reason: .phrase, duration: 600),
    ])
  }

  @Test
  func weekTotalsAreTheBucketSums() {
    let startOfToday = calendar.startOfDay(for: now)
    let stats = LockHistoryStats.compute(entries: [
      entry(
        start: startOfToday.addingTimeInterval(-3600),
        end: startOfToday.addingTimeInterval(-1800),
        reason: .explicit
      ),
      // Monday of this week.
      entry(
        start: startOfToday.addingTimeInterval(-2 * 24 * 3600),
        end: startOfToday.addingTimeInterval(-2 * 24 * 3600 + 1200),
        reason: .gesture
      ),
    ], now: now, calendar: calendar)

    #expect(stats.weekCount == 2)
    #expect(stats.weekDuration == 3000)
    #expect(stats.weekCount == stats.dailyActivity.reduce(0) { $0 + $1.count })
    #expect(stats.weekDuration == stats.dailyActivity.reduce(0) { $0 + $1.duration })
  }

  @Test
  func entryBeforeThisCalendarWeekCountsOnlyForReasons() {
    // Ended one hour before this week's Sunday midnight: a trailing-7-days window would still
    // catch this, but the chart's calendar-week buckets must not, or the totals would outgrow
    // the chart they summarize.
    let startOfToday = calendar.startOfDay(for: now)
    let stats = LockHistoryStats.compute(entries: [
      entry(
        start: startOfToday.addingTimeInterval(-3 * 24 * 3600 - 3 * 3600),
        end: startOfToday.addingTimeInterval(-3 * 24 * 3600 - 3600),
        reason: .autoUnlock
      ),
    ], now: now, calendar: calendar)

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

  @Test
  func lockCountFormatting() {
    #expect(LockHistoryStats.formatLockCount(0) == "0 locks")
    #expect(LockHistoryStats.formatLockCount(1) == "1 lock")
    #expect(LockHistoryStats.formatLockCount(12) == "12 locks")
  }

  private func entry(start: Date, end: Date, reason: UnlockRecord.Reason) -> LockHistoryEntry {
    LockHistoryEntry(startedAt: start, endedAt: end, reason: reason)
  }
}
