import Core
import SwiftUI

// MARK: - Shared Header Components

struct AppTitleHeaderView: View {
  var body: some View {
    VStack(spacing: 16) {
      HStack {
        Image(systemName: "lock.shield.fill")
          .foregroundColor(.accentColor)
          .font(.title2)
        Text(LocalizationKey.appTitle.localized)
          .font(.title2)
          .fontWeight(.semibold)
      }
      .padding(.top, 16)

      Divider()
    }
  }
}

// MARK: - Quick Actions Components

struct QuickActionsView: View {
  let keyboardManager: KeyboardLockManager

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(LocalizationKey.quickActions.localized)
        .font(.headline)
        .foregroundColor(.secondary)

      VStack(spacing: 6) {
        NavigationLink(
          destination: SettingsView().environmentObject(keyboardManager)
        ) {
          SettingRow(
            icon: "gear",
            title: LocalizationKey.settingsTitle.localized,
            subtitle: LocalizationKey.settingsSubtitle.localized
          )
        }
        .buttonStyle(PlainButtonStyle())

        NavigationLink(destination: AboutView()) {
          SettingRow(
            icon: "info.circle",
            title: LocalizationKey.aboutTitle.localized,
            subtitle: LocalizationKey.aboutSubtitle.localized
          )
        }
        .buttonStyle(PlainButtonStyle())
      }
    }
  }
}

// MARK: - Bottom Actions

struct BottomActionsView: View {
  var body: some View {
    HStack {
      Text(LocalizationKey.shortcutHint.localized)
        .font(.caption)
        .foregroundColor(.secondary)

      Spacer()

      Button(LocalizationKey.actionQuit.localized) {
        NSApplication.shared.terminate(nil)
      }
      .buttonStyle(PlainButtonStyle())
      .foregroundColor(.red)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
  }
}

// MARK: - Setting Row Component

struct SettingRow: View {
  let icon: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(.accentColor)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
          .foregroundColor(.primary)
        Text(subtitle)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .foregroundColor(.secondary)
        .font(.caption)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}
