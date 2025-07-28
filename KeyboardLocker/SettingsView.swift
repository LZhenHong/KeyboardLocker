import Core
import SwiftUI

struct SettingsView: View {
  @ObservedObject private var coreConfig = CoreConfiguration.shared

  // Auto-lock duration options (in seconds)
  private let durationOptions: [(Int, String)] = [
    (0, "Never"),
    (900, "15 minutes"),
    (1800, "30 minutes"),
    (3600, "1 hour"),
    (7200, "2 hours"),
    (14400, "4 hours"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      // Auto-lock settings
      VStack(alignment: .leading, spacing: 12) {
        Text(LocalizationKey.settingsAutoLock.localized)
          .font(.headline)
          .foregroundColor(.primary)

        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Picker("Auto-lock Duration", selection: $coreConfig.autoLockDuration) {
              ForEach(durationOptions, id: \.0) { value, label in
                Text(label).tag(value)
              }
            }
            .pickerStyle(MenuPickerStyle())
          }

          // Show current activity status if auto-lock is enabled
          if coreConfig.autoLockDuration > 0 {
            HStack {
              Image(systemName: "timer")
                .foregroundColor(.secondary)
              Text("Starts counting when you stop typing or using the mouse")
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

      // Notification settings
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
          coreConfig.resetToDefaults()
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
