import SwiftUI

struct ContentView: View {
  @State private var isKeyboardLocked = false
  @State private var lockDurationTimer: Timer?
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
      setupLockDurationTimer()
    }
    .onReceive(keyboardManager.$isLocked) { locked in
      isKeyboardLocked = locked
      setupLockDurationTimer()
    }
    .onDisappear {
      lockDurationTimer?.invalidate()
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
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Circle()
              .fill(isKeyboardLocked ? Color.red : Color.green)
              .frame(width: 12, height: 12)
            Text(
              isKeyboardLocked
                ? LocalizationKey.statusLocked.localized
                : LocalizationKey.statusUnlocked.localized
            )
            .font(.body)
            .foregroundColor(.primary)
            Spacer()
          }

          // Show lock duration when locked
          if isKeyboardLocked, let durationString = keyboardManager.getLockDurationString() {
            HStack {
              Image(systemName: "clock")
                .foregroundColor(.secondary)
                .font(.caption)
              Text(LocalizationKey.lockDurationFormat.localized(durationString))
                .font(.caption)
                .foregroundColor(.secondary)
              Spacer()
            }
            .padding(.leading, 16) // Align with status text
          }

          // Show auto-lock status when enabled and not locked
          if !isKeyboardLocked, keyboardManager.isAutoLockEnabled {
            HStack {
              Image(systemName: "timer")
                .foregroundColor(.orange)
                .font(.caption)
              Text("Auto-lock: \(autoLockStatusText)")
                .font(.caption)
                .foregroundColor(.secondary)
              Spacer()
            }
            .padding(.leading, 16)
          }
        }

        // Lock/unlock button
        VStack {
          HStack {
            Image(systemName: isKeyboardLocked ? "lock.open" : "lock")
            Text(
              isKeyboardLocked
                ? LocalizationKey.actionUnlock.localized
                : LocalizationKey.actionLock.localized)
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

  private func setupLockDurationTimer() {
    // Invalidate existing timer
    lockDurationTimer?.invalidate()

    // Only start timer when locked
    if isKeyboardLocked {
      lockDurationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        // Force UI update by triggering objectWillChange
        DispatchQueue.main.async {
          keyboardManager.objectWillChange.send()
        }
      }
    }
  }

  /// Get auto-lock status text for display
  private var autoLockStatusText: String {
    let duration = keyboardManager.autoLockDuration
    if duration == 0 {
      return "Disabled"
    }

    // Get time since last activity
    let timeSinceActivity = keyboardManager.getTimeSinceLastActivity()
    let remainingTime = max(0, TimeInterval(duration * 60) - timeSinceActivity)

    if remainingTime > 0 {
      let minutes = Int(remainingTime / 60)
      let seconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))
      return String(format: "%02d:%02d", minutes, seconds)
    } else {
      return "Ready to lock"
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
