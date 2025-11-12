import Core
import SwiftUI

struct StatusSectionView: View {
  let isKeyboardLocked: Bool
  @EnvironmentObject private var keyboardManager: KeyboardLockManager

  private var statusText: String {
    isKeyboardLocked
      ? LocalizationKey.statusLocked.localized
      : LocalizationKey.statusUnlocked.localized
  }

  private var mainStatusView: some View {
    HStack {
      Circle()
        .fill(isKeyboardLocked ? Color.red : Color.green)
        .frame(width: 12, height: 12)

      Text(statusText)
        .font(.body)
        .foregroundColor(.primary)

      Spacer()
    }
  }

  private var autoLockStatusView: some View {
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      HStack {
        Image(systemName: "timer")
          .foregroundColor(.orange)
          .font(.caption)
        Text(LocalizationKey.autoLockStatus.localized(keyboardManager.autoLockStatusText))
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
      }
      .padding(.leading, 16)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      mainStatusView

      if isKeyboardLocked {
        LockDurationRow()
      }

      if !isKeyboardLocked, keyboardManager.isAutoLockEnabled {
        autoLockStatusView
      }
    }
  }
}

private struct LockDurationRow: View {
  @EnvironmentObject private var keyboardManager: KeyboardLockManager

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      if let durationText = keyboardManager.lockDurationText {
        let displayText = getLockDurationDisplayText(durationText)
        if !displayText.isEmpty {
          HStack {
            Image(systemName: "clock")
              .foregroundColor(.secondary)
              .font(.caption)
            Text(displayText)
              .font(.caption)
              .foregroundColor(.secondary)
            Spacer()
          }
          .padding(.leading, 16)
        }
      }
    }
  }

  private func getLockDurationDisplayText(_ durationString: String) -> String {
    if durationString.contains(":") {
      LocalizationKey.lockDurationFormat.localized(durationString)
    } else {
      // Fallback: show a generic message
      LocalizationKey.statusLocked.localized()
    }
  }
}
