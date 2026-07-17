import Client
import SwiftUI
import WidgetKit

struct KeyboardLockerStatusWidget: Widget {
  static let kind = "io.lzhlovesjyq.keyboardlocker.status"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: Self.kind,
      provider: KeyboardLockerTimelineProvider()
    ) { entry in
      KeyboardLockerWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Keyboard Lock Status")
    .description("Shows the authoritative KeyboardLocker state and auto-unlock deadline.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct KeyboardLockerWidgetEntryView: View {
  let entry: KeyboardLockerWidgetEntry

  var body: some View {
    content
      .padding()
      .modifier(KeyboardLockerWidgetBackground())
  }

  @ViewBuilder
  private var content: some View {
    switch entry.state {
    case let .available(snapshot):
      VStack(alignment: .leading, spacing: 8) {
        Label("KeyboardLocker", systemImage: snapshot.isLocked ? "keyboard.fill" : "keyboard")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(snapshot.isLocked ? "Locked" : "Unlocked")
          .font(.title2.weight(.semibold))

        if snapshot.isLocked {
          if let deadline = snapshot.autoUnlockTargetDate {
            Label {
              Text(deadline, style: .timer)
                .monospacedDigit()
            } icon: {
              Image(systemName: "timer")
            }
          } else {
            Label("Manual unlock", systemImage: "infinity")
          }

          Label(snapshot.settings.unlockHotkey.displayString, systemImage: "command")
        } else {
          Label("Ready", systemImage: "checkmark.circle")
        }
      }

    case let .unavailable(message):
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Agent Unavailable")
          .font(.headline)
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
    }
  }
}

private struct KeyboardLockerWidgetBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 14.0, *) {
      content.containerBackground(.fill.tertiary, for: .widget)
    } else {
      content.background(.background)
    }
  }
}
