import Charts
import Client
import SwiftUI

/// The popover's statistics page: how often and how long the keyboard gets locked, aggregated
/// from the Agent's bounded history. Like the settings page, it stores nothing of its own —
/// every value comes from `store`, and a read failure is shown honestly rather than replaced
/// with an empty list.
struct StatsPage: View {
  @ObservedObject var store: AppUIStore
  let goBack: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      content
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    .onAppear {
      store.loadLockHistory()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 6) {
      Button(action: goBack) {
        Label("Back", systemImage: "chevron.backward")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.borderless)

      Spacer(minLength: 0)

      Text("Statistics")
        .font(.headline)

      Spacer(minLength: 0)

      // Balances the leading back button so the title stays centered.
      Label("Back", systemImage: "chevron.backward")
        .labelStyle(.titleAndIcon)
        .hidden()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  // MARK: - Body

  @ViewBuilder
  private var content: some View {
    switch store.historyState {
    case let .unavailable(message):
      UnavailableRow(message: message) {
        store.loadLockHistory()
      }

    case .idle, .loading:
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Reading history…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

    case .loaded:
      if let stats = store.historyStats, !stats.isEmpty {
        sections(stats)
      } else {
        Text("No completed locks yet. Statistics appear after the first unlock.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func sections(_ stats: LockHistoryStats) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      statsSection("Today") {
        statsRow("Locks", value: "\(stats.todayCount)")
        rowDivider
        statsRow("Total Locked", value: LockHistoryStats.formatDuration(stats.todayDuration))
      }

      statsSection("This Week") {
        weekChart(stats)
        rowDivider
        statsRow(
          "Total",
          value: "\(LockHistoryStats.formatLockCount(stats.weekCount)) · \(LockHistoryStats.formatDuration(stats.weekDuration))"
        )
      }

      statsSection("By Unlock Method") {
        shareLine(stats.reasonCounts)
          .padding(.horizontal, 8)
          .padding(.top, 10)
        legendRow(stats.reasonCounts)
          .padding(.horizontal, 12)
          .padding(.top, 6)
          .padding(.bottom, 10)
      }

      Text("Keeps the \(LockHistory.retentionLimit) most recent locks. A lock counts toward the day it ended.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
    }
  }

  // MARK: - Section pieces

  private func statsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.medium))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)

      VStack(spacing: 0) {
        content()
      }
      .background(
        Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
  }

  private func statsRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
      Spacer(minLength: 12)
      Text(value)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
  }

  /// Indented so the line separates the row contents rather than the card edges.
  private var rowDivider: some View {
    Divider()
      .padding(.leading, 12)
  }

  // MARK: - Charts

  /// Seven bars of locked time, Sunday through Saturday; days after today stay empty and their
  /// labels dim. The y-axis stays hidden: exact totals live in the row below and per-bar
  /// accessibility values, and a labeled axis would crowd a 320pt popover without adding
  /// information the rows don't already carry.
  private func weekChart(_ stats: LockHistoryStats) -> some View {
    let todayStart = stats.todayStart
    let weekStart = stats.dailyActivity[0].dayStart
    // Through the end of Saturday; the automatic domain drops the edge-most axis label.
    let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)!
    return Chart {
      ForEach(stats.dailyActivity, id: \.dayStart) { day in
        // Marks sharing one x stack bottom-up in declaration order; the model already sorted
        // segments most-frequent-first, so the biggest segment grounds each bar.
        ForEach(day.durationByMethod, id: \.reason) { segment in
          BarMark(
            // `unit: .day` is load-bearing: without it Swift Charts renders this date scale
            // in reverse and logs a fixed-dimension fallback warning.
            x: .value("Day", day.dayStart, unit: .day),
            y: .value("Locked", segment.duration),
            // Two-fifths of the day slot; any width stays centered, so labels stay aligned.
            width: .ratio(0.4)
          )
          .foregroundStyle(
            Self.methodColor(for: segment.reason, in: stats)
              .opacity(day.dayStart == todayStart ? 1 : 0.45)
          )
          .accessibilityLabel(
            Text("\(day.dayStart.formatted(.dateTime.weekday(.wide))), \(segment.reason.displayName)")
          )
          .accessibilityValue("\(LockHistoryStats.formatDuration(segment.duration)) locked")
        }
      }
    }
    .chartYAxis(.hidden)
    .chartXScale(domain: weekStart ... weekEnd)
    .chartXAxis {
      // Labels anchor at each day's center so they sit under the middle of the day-wide bars.
      // `preset: .aligned` is load-bearing: the default preset shifts labels ~9pt right of the
      // marks they annotate (measured against rendered bars), which reads as bar/label drift.
      AxisMarks(preset: .aligned, values: stats.dailyActivity.map { $0.dayStart.addingTimeInterval(12 * 3600) }) { value in
        AxisValueLabel {
          if let date = value.as(Date.self) {
            let dayStart = Calendar.current.startOfDay(for: date)
            Text(date, format: .dateTime.weekday(.narrow))
              .font(.caption2.weight(dayStart == todayStart ? .semibold : .regular))
              .opacity(dayStart > todayStart ? 0.4 : 1)
          }
        }
      }
    }
    .frame(height: 96)
    .padding(.horizontal, 12)
    .padding(.top, 10)
    .padding(.bottom, 8)
  }

  /// One segmented line: every method's color, width = share of all unlocks, inset 8pt from
  /// the card edges. Decorative — the legend row carries the same information accessibly.
  private func shareLine(_ reasonCounts: [LockHistoryStats.ReasonCount]) -> some View {
    let total = reasonCounts.reduce(0) { $0 + $1.count }
    return GeometryReader { proxy in
      // A 1pt hairline of card background between segments: two saturated colors touching on a
      // dark card read as a vertical step that isn't there (chromatic contrast).
      let gap: CGFloat = 1
      let available = proxy.size.width - gap * CGFloat(max(0, reasonCounts.count - 1))
      HStack(spacing: gap) {
        ForEach(Array(reasonCounts.enumerated()), id: \.element.reason) { index, reasonCount in
          Rectangle()
            .fill(Self.methodColor(at: index))
            .frame(width: available * CGFloat(reasonCount.count) / CGFloat(max(total, 1)))
        }
      }
    }
    .frame(height: 4)
    .clipShape(Capsule(style: .continuous))
    .accessibilityHidden(true)
  }

  /// The legend spreads across the same column the share line spans: leftmost item flush left,
  /// rightmost flush right, so line and legend bracket the identical width.
  private func legendRow(_ reasonCounts: [LockHistoryStats.ReasonCount]) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(reasonCounts.enumerated()), id: \.element.reason) { index, reasonCount in
        if index > 0 {
          Spacer(minLength: 8)
        }
        HStack(spacing: 4) {
          Circle()
            .fill(Self.methodColor(at: index))
            .frame(width: 6, height: 6)
          Text(reasonCount.reason.displayName)
          Text("\(reasonCount.count)")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      }
    }
    .font(.callout)
  }

  /// Stable per-rank palette: the most frequent method always takes blue, the second orange,
  /// so the colors the user memorizes stay put between openings.
  private static func methodColor(at index: Int) -> Color {
    let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo]
    return palette[index % palette.count]
  }

  /// A method's color is its rank in the overall histogram, so a day-bar segment and the
  /// share line always mean the same thing with the same color.
  private static func methodColor(
    for reason: UnlockRecord.Reason,
    in stats: LockHistoryStats
  ) -> Color {
    methodColor(at: stats.reasonCounts.firstIndex { $0.reason == reason } ?? 0)
  }
}

/// Shared presentation for an agent value the app could not read.
private struct UnavailableRow: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text("Statistics are unavailable")
          Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
      Button("Try Again", action: retry)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
