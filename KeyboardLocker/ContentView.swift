import SwiftUI

struct ContentView: View {
  @State private var isKeyboardLocked = false
  @EnvironmentObject var permissionManager: PermissionManager
  @EnvironmentObject var keyboardManager: KeyboardLockManager

  var body: some View {
    NavigationStack {
      if permissionManager.hasAccessibilityPermission {
        authorizedView
      } else {
        unauthorizedView
      }
    }
    .frame(width: 300)
    .background(Color(NSColor.windowBackgroundColor))
    .onAppear {
      permissionManager.checkAllPermissions()
      isKeyboardLocked = keyboardManager.isLocked
    }
    .onReceive(keyboardManager.$isLocked) { locked in
      isKeyboardLocked = locked
    }
  }

  // MARK: - Shared Components

  private var appTitleHeader: some View {
    VStack(spacing: 16) {
      HStack {
        Image(systemName: "lock.shield.fill")
          .foregroundColor(.blue)
          .font(.title2)
        Text(LocalizationKey.appTitle.localized)
          .font(.title2)
          .fontWeight(.semibold)
      }
      .padding(.top, 16)

      Divider()
    }
  }

  // MARK: - Authorized View (Main Interface)

  private var authorizedView: some View {
    VStack(spacing: 16) {
      appTitleHeader

      // Main functionality area
      VStack(spacing: 16) {
        // Lock status indicator
        HStack {
          Circle()
            .fill(isKeyboardLocked ? Color.red : Color.green)
            .frame(width: 12, height: 12)
          Text(
            isKeyboardLocked
              ? LocalizationKey.statusLocked.localized : LocalizationKey.statusUnlocked.localized
          )
          .font(.body)
          .foregroundColor(.primary)
          Spacer()
        }

        // Lock/unlock button
        VStack {
          HStack {
            Image(systemName: isKeyboardLocked ? "lock.open" : "lock")
            Text(
              isKeyboardLocked
                ? LocalizationKey.actionUnlock.localized : LocalizationKey.actionLock.localized)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(isKeyboardLocked ? Color.red : Color.green)
          .foregroundColor(.white)
          .cornerRadius(8)
          .onTapGesture {
            toggleKeyboardLock()
          }
        }

        // Quick navigation
        VStack(alignment: .leading, spacing: 12) {
          Text(LocalizationKey.quickActions.localized)
            .font(.headline)
            .foregroundColor(.secondary)

          VStack(spacing: 6) {
            NavigationLink(destination: SettingsView().environmentObject(keyboardManager)) {
              SettingRow(
                icon: "gear", title: LocalizationKey.settingsTitle.localized,
                subtitle: LocalizationKey.settingsSubtitle.localized
              )
            }
            .buttonStyle(PlainButtonStyle())

            NavigationLink(destination: AboutView()) {
              SettingRow(
                icon: "info.circle", title: LocalizationKey.aboutTitle.localized,
                subtitle: LocalizationKey.aboutSubtitle.localized
              )
            }
            .buttonStyle(PlainButtonStyle())
          }
        }
      }
      .padding(.horizontal, 16)

      // Bottom actions
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

  // MARK: - Unauthorized View (Permission Required)

  private var unauthorizedView: some View {
    VStack(spacing: 20) {
      appTitleHeader

      // Permission required content
      VStack(spacing: 16) {
        // Warning icon
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
          .font(.system(size: 48))

        // Title
        Text(LocalizationKey.permissionRequired.localized)
          .font(.title2)
          .fontWeight(.semibold)
          .multilineTextAlignment(.center)

        // Description
        Text(LocalizationKey.permissionDescription.localized)
          .font(.body)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        // Authorization button
        Button(action: {
          permissionManager.requestAccessibilityPermission()
        }) {
          HStack {
            Image(systemName: "gear")
            Text(LocalizationKey.openSystemPreferences.localized)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 8)

        // Auto-detection status info
        HStack {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.caption)
          Text(LocalizationKey.autoDetectionEnabled.localized)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.top, 8)
      }
      .padding(.horizontal, 16)

      Spacer()

      // Bottom quit button
      HStack {
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

  // MARK: - Helper Methods

  private func toggleKeyboardLock() {
    if isKeyboardLocked {
      keyboardManager.unlockKeyboard()
    } else {
      keyboardManager.lockKeyboard()
    }
  }
}

struct SettingRow: View {
  let icon: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(.blue)
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

#Preview {
  ContentView()
    .environmentObject(KeyboardLockManager())
    .environmentObject(PermissionManager())
}
