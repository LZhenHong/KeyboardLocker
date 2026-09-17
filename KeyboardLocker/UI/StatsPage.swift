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

      statsSection("Last 7 Days") {
        statsRow("Locks", value: "\(stats.weekCount)")
        rowDivider
        statsRow("Total Locked", value: LockHistoryStats.formatDuration(stats.weekDuration))
      }

      statsSection("By Unlock Method") {
        ForEach(Array(stats.reasonCounts.enumerated()), id: \.element.reason) {
          index, reasonCount in
          if index > 0 {
            rowDivider
          }
          statsRow(reasonCount.reason.displayName, value: "\(reasonCount.count)")
        }
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
