import Core
import SwiftUI

struct StatusSectionView: View {
  let isKeyboardLocked: Bool
  let keyboardManager: KeyboardLockManager

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      MainStatusRow(isLocked: isKeyboardLocked)

      if isKeyboardLocked {
        LockDurationRow(keyboardManager: keyboardManager)
      }

      if !isKeyboardLocked, keyboardManager.isAutoLockEnabled {
        AutoLockStatusRow(keyboardManager: keyboardManager)
      }
    }
  }
}

private struct MainStatusRow: View {
  let isLocked: Bool

  var body: some View {
    HStack {
      StatusIndicator(isLocked: isLocked)
      StatusText(isLocked: isLocked)
      Spacer()
    }
  }
}

private struct StatusIndicator: View {
  let isLocked: Bool

  var body: some View {
    Circle()
      .fill(isLocked ? Color.red : Color.green)
      .frame(width: 12, height: 12)
  }
}

private struct StatusText: View {
  let isLocked: Bool

  var body: some View {
    Text(statusText)
      .font(.body)
      .foregroundColor(.primary)
  }

  private var statusText: String {
    isLocked
      ? LocalizationKey.statusLocked.localized
      : LocalizationKey.statusUnlocked.localized
  }
}

private struct LockDurationRow: View {
  let keyboardManager: KeyboardLockManager

  var body: some View {
    if let durationString = keyboardManager.getLockDurationString() {
      let displayText = getLockDurationDisplayText(durationString)
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
    durationString.contains(":")
      ? LocalizationKey.timedLockRemaining.localized(durationString)
      : ""
  }
}

private struct AutoLockStatusRow: View {
  let keyboardManager: KeyboardLockManager

  var body: some View {
    HStack {
      Image(systemName: "timer")
        .foregroundColor(.orange)
        .font(.caption)
      Text(LocalizationKey.autoLockStatus.localized(getAutoLockStatusText()))
        .font(.caption)
        .foregroundColor(.secondary)
      Spacer()
    }
    .padding(.leading, 16)
  }

  private func getAutoLockStatusText() -> String {
    let duration = keyboardManager.autoLockDuration
    if duration == 0 {
      return LocalizationKey.autoLockDisabled.localized
    }

    let timeSinceActivity = keyboardManager.getTimeSinceLastActivity()
    let remainingTime = max(0, TimeInterval(duration * 60) - timeSinceActivity)

    if remainingTime > 0 {
      return CountdownFormatter.countdownString(from: remainingTime)
    } else {
      return LocalizationKey.autoLockReadyToLock.localized
    }
  }
}
