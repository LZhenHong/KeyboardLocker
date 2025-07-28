import Core
import SwiftUI

struct SettingsView: View {
  @ObservedObject private var coreConfig = CoreConfiguration.shared

  private typealias AutoLockInterval = CoreConfiguration.AutoLockDuration

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      autoLockSection
      notificationSection
      keyboardSection
      Spacer()
      resetSection
    }
    .padding()
    .navigationTitle(LocalizationKey.settingsTitle.localized)
    .frame(width: 300)
  }

  // MARK: - View Components

  private var autoLockSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(LocalizationKey.settingsAutoLock.localized)
        .font(.headline)
        .foregroundColor(.primary)

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Picker(
            LocalizationKey.timeAutoLockDuration.localized, selection: $coreConfig.autoLockDuration
          ) {
            ForEach(LockDurationHelper.autoLockPresets, id: \.self) { duration in
              Text(LockDurationHelper.localizedDisplayString(for: duration))
                .tag(duration)
            }
          }
          .pickerStyle(MenuPickerStyle())
        }

        // Show current activity status if auto-lock is enabled
        if coreConfig.autoLockDuration.isEnabled {
          HStack {
            Image(systemName: "timer")
              .foregroundColor(.secondary)
            Text(LocalizationKey.timeActivityText.localized)
              .font(.caption)
              .foregroundColor(.secondary)
            Spacer()
          }
        }

        Text(LocalizationKey.settingsAutoLockDescription.localized)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(12)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
    }
  }

  private var notificationSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(LocalizationKey.settingsNotifications.localized)
        .font(.headline)
        .foregroundColor(.primary)

      VStack(alignment: .leading, spacing: 12) {
        Toggle(
          LocalizationKey.settingsShowNotifications.localized,
          isOn: $coreConfig.showNotifications
        )

        Text(LocalizationKey.settingsNotificationsDescription.localized)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(12)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
    }
  }

  private var keyboardSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(LocalizationKey.settingsKeyboard.localized)
        .font(.headline)
        .foregroundColor(.primary)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(LocalizationKey.actionLock.localized + "/" + LocalizationKey.actionUnlock.localized + ":")
          Spacer()
          Text("⌘ + ⌥ + L".localized)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }

        Text(LocalizationKey.settingsKeyboardDescription.localized)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(12)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
    }
  }

  private var resetSection: some View {
    HStack {
      Spacer()
      Button(LocalizationKey.settingsReset.localized) {
        coreConfig.resetToDefaults()
      }
      .buttonStyle(PlainButtonStyle())
      .foregroundColor(.red)
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView()
      .environmentObject(KeyboardLockManager())
  }
}
