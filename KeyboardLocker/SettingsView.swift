import SwiftUI

struct SettingsView: View {
  @StateObject private var appConfig = AppConfiguration.shared
  @EnvironmentObject var keyboardManager: KeyboardLockManager

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      // Auto-lock settings
      VStack(alignment: .leading, spacing: 12) {
        Text(LocalizationKey.settingsAutoLock.localized)
          .font(.headline)
          .foregroundColor(.primary)

        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text(LocalizationKey.settingsAutoLockTime.localized)
            Spacer()
            Picker("", selection: $appConfig.autoLockDuration) {
              Text(LocalizationKey.time15Minutes.localized).tag(15)
              Text(LocalizationKey.time30Minutes.localized).tag(30)
              Text(LocalizationKey.time60Minutes.localized).tag(60)
              Text(LocalizationKey.timeNever.localized).tag(0)
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 100)
            .onChange(of: appConfig.autoLockDuration) { _ in
              keyboardManager.updateAutoLockSettings()
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

      // Notification settings
      VStack(alignment: .leading, spacing: 12) {
        Text(LocalizationKey.settingsNotifications.localized)
          .font(.headline)
          .foregroundColor(.primary)

        VStack(alignment: .leading, spacing: 12) {
          Toggle(LocalizationKey.settingsShowNotifications.localized, isOn: $appConfig.showNotifications)

          Text(LocalizationKey.settingsNotificationsDescription.localized)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
      }

      // Keyboard shortcut description
      VStack(alignment: .leading, spacing: 12) {
        Text(LocalizationKey.settingsKeyboard.localized)
          .font(.headline)
          .foregroundColor(.primary)

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(
              LocalizationKey.actionLock.localized + "/" + LocalizationKey.actionUnlock.localized
                + ":")
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

      Spacer()

      // Reset button
      HStack {
        Spacer()
        Button(LocalizationKey.settingsReset.localized) {
          appConfig.resetToDefaults()
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(.red)
      }
    }
    .padding()
    .navigationTitle(LocalizationKey.settingsTitle.localized)
    .frame(width: 300)
  }
}

#Preview {
  NavigationStack {
    SettingsView()
      .environmentObject(KeyboardLockManager())
  }
}
