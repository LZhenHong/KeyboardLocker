import Core
import SwiftUI

struct TimedLockControlsView: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    VStack(spacing: 12) {
      TimedLockHeader()
      PresetButtonsSection(state: state)
      Divider()
      CustomDurationSection(state: state)
    }
  }
}

private struct TimedLockHeader: View {
  var body: some View {
    HStack {
      Text(LocalizationKey.timedLockTitle.localized)
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(.primary)
      Spacer()
    }
  }
}

private struct PresetButtonsSection: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        ForEach(Array(LockDurationHelper.timedLockPresets.prefix(2)), id: \.self) { duration in
          PresetButton(duration: duration, action: { state.startTimedLock(with: duration) })
        }
      }

      HStack(spacing: 8) {
        ForEach(Array(LockDurationHelper.timedLockPresets.suffix(2)), id: \.self) { duration in
          PresetButton(duration: duration, action: { state.startTimedLock(with: duration) })
        }
      }
    }
  }
}

private struct CustomDurationSection: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    VStack(spacing: 8) {
      CustomDurationHeader()
      CustomDurationControls(state: state)
    }
  }
}

private struct CustomDurationHeader: View {
  var body: some View {
    HStack {
      Text(LocalizationKey.timedLockCustom.localized)
        .font(.caption)
        .foregroundColor(.secondary)
      Spacer()
    }
  }
}

private struct CustomDurationControls: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    HStack(spacing: 8) {
      TextField("", text: state.customMinutesString)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .frame(width: 60)
        .onSubmit(state.startCustomTimedLock)

      Text(LocalizationKey.timeMinutes.localized)
        .font(.caption)
        .foregroundColor(.secondary)

      Spacer()

      CustomLockButton(action: state.startCustomTimedLock)
    }
  }
}

private struct CustomLockButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Image(systemName: "timer")
        Text(LocalizationKey.timedLockStart.localized)
      }
      .font(.caption)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color.orange)
      .foregroundColor(.white)
      .cornerRadius(8)
    }
    .buttonStyle(PlainButtonStyle())
  }
}

struct PresetButton: View {
  let duration: CoreConfiguration.Duration
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(LockDurationHelper.localizedDisplayString(for: duration))
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange)
        .foregroundColor(.white)
        .cornerRadius(16)
    }
    .buttonStyle(PlainButtonStyle())
  }
}
