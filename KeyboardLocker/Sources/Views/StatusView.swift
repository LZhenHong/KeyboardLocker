import Core
import SwiftUI

struct StatusSectionView: View {
  let isKeyboardLocked: Bool
  @ObservedObject var keyboardManager: KeyboardLockManager

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

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      mainStatusView

      if isKeyboardLocked {
        LockDurationRow(keyboardManager: keyboardManager)
      }

      if !isKeyboardLocked, keyboardManager.isAutoLockEnabled {
        autoLockStatusView
      }
    }
  }
}

private struct LockDurationRow: View {
  @ObservedObject var keyboardManager: KeyboardLockManager

  var body: some View {
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

  private func getLockDurationDisplayText(_ durationString: String) -> String {
    if durationString.contains(":") {
      // Check if it's a timed lock with remaining time
      if keyboardManager.isTimedLock {
        LocalizationKey.timedLockRemaining.localized(durationString)
      } else {
        // Regular lock showing elapsed time
        LocalizationKey.lockDurationFormat.localized(durationString)
      }
    } else {
      // Fallback: show a generic message
      LocalizationKey.statusLocked.localized()
    }
  }
}
