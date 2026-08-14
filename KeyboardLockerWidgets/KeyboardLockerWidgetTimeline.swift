import Client
import Foundation
import WidgetKit

struct KeyboardLockerWidgetEntry: TimelineEntry, Equatable {
  enum State: Equatable {
    case available(LockStatusSnapshot)
    case unavailable(message: String)
  }

  let date: Date
  let state: State

  static func placeholder(at date: Date) -> Self {
    Self(
      date: date,
      state: .available(
        LockStatusSnapshot(
          capturedAt: date,
          isLocked: true,
          startedAt: date.addingTimeInterval(-5 * 60),
          autoUnlockTargetDate: date.addingTimeInterval(60),
          settings: .default
        )
      )
    )
  }
}

struct KeyboardLockerWidgetSnapshotLoader: Sendable {
  typealias FetchSnapshot = @Sendable () async throws -> LockStatusSnapshot

  static let regularRefreshInterval: TimeInterval = 15 * 60

  private let fetchSnapshot: FetchSnapshot

  init(fetchSnapshot: @escaping FetchSnapshot) {
    self.fetchSnapshot = fetchSnapshot
  }

  static var live: Self {
    Self {
      try await XPCClient.shared.lockStatusSnapshot()
    }
  }

  func entry(at date: Date) async -> KeyboardLockerWidgetEntry {
    do {
      return try await KeyboardLockerWidgetEntry(
        date: date,
        state: .available(fetchSnapshot())
      )
    } catch {
      return KeyboardLockerWidgetEntry(
        date: date,
        state: .unavailable(message: Self.message(for: error))
      )
    }
  }

  func nextRefreshDate(
    after entry: KeyboardLockerWidgetEntry,
    now: Date
  ) -> Date {
    let regularRefresh = now.addingTimeInterval(Self.regularRefreshInterval)
    guard case let .available(snapshot) = entry.state,
          snapshot.isLocked,
          let deadline = snapshot.autoUnlockTargetDate
    else {
      return regularRefresh
    }

    // Reconcile just after the Agent's deadline instead of presenting an expired countdown until
    // the next regular refresh. WidgetKit remains free to coalesce the requested reload.
    let deadlineRefresh = max(
      now.addingTimeInterval(1),
      deadline.addingTimeInterval(1)
    )
    return min(regularRefresh, deadlineRefresh)
  }

  private static func message(for error: Error) -> String {
    let error = error as NSError
    return [error.localizedDescription, error.localizedRecoverySuggestion]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

struct KeyboardLockerTimelineProvider: TimelineProvider {
  private let loader: KeyboardLockerWidgetSnapshotLoader

  init(loader: KeyboardLockerWidgetSnapshotLoader = .live) {
    self.loader = loader
  }

  func placeholder(in _: Context) -> KeyboardLockerWidgetEntry {
    .placeholder(at: Date())
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping @Sendable (KeyboardLockerWidgetEntry) -> Void
  ) {
    guard !context.isPreview else {
      completion(.placeholder(at: Date()))
      return
    }

    Task {
      await completion(loader.entry(at: Date()))
    }
  }

  func getTimeline(
    in _: Context,
    completion: @escaping @Sendable (Timeline<KeyboardLockerWidgetEntry>) -> Void
  ) {
    Task {
      let now = Date()
      let entry = await loader.entry(at: now)
      let refreshDate = loader.nextRefreshDate(after: entry, now: now)
      completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
  }
}
