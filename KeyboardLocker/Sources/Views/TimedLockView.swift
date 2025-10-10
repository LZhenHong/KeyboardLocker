import Core
import SwiftUI

private typealias LockInterval = CoreConfiguration.Duration

struct TimedLockControlsView: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text(LocalizationKey.timedLockTitle.localized)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.primary)
        Spacer()
      }
      PresetButtonsSection(state: state)
      Divider()
      CustomDurationSection(state: state)
    }
  }
}

private struct PresetButtonsSection: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    let presets = LockInterval.timedLockPresets
    let columns = [
      GridItem(.flexible()),
      GridItem(.flexible()),
      GridItem(.flexible()),
      GridItem(.flexible()),
    ]

    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(presets, id: \.self) { duration in
        PresetButton(duration: duration, action: { state.startTimedLock(with: duration) })
      }
    }
  }
}

private struct CustomDurationSection: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text(LocalizationKey.timedLockCustom.localized)
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
      }
      CustomDurationControls(state: state)
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

      Button(action: state.startCustomTimedLock) {
        HStack {
          Image(systemName: "timer")
          Text(LocalizationKey.timedLockStart.localized)
        }
        .font(.caption)
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
      }
      .background(Color.orange)
      .cornerRadius(8)
      .buttonStyle(PlainButtonStyle())
    }
  }
}

struct PresetButton: View {
  let duration: CoreConfiguration.Duration
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(duration.localized)
        .font(.caption)
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    .background(Color.orange)
    .cornerRadius(16)
    .buttonStyle(PlainButtonStyle())
  }
}
