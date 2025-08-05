import Core
import SwiftUI

struct PermissionRequiredView: View {
  let permissionManager: PermissionManager

  var body: some View {
    VStack(spacing: 20) {
      AppTitleHeaderView()
      PermissionContent(permissionManager: permissionManager)
      Spacer()
      QuitButton()
    }
  }
}

private struct PermissionContent: View {
  let permissionManager: PermissionManager

  var body: some View {
    VStack(spacing: 16) {
      WarningIcon()
      PermissionTexts()
      PermissionButton(permissionManager: permissionManager)
    }
    .padding(.horizontal, 16)
  }
}

private struct WarningIcon: View {
  var body: some View {
    Image(systemName: "exclamationmark.triangle.fill")
      .foregroundColor(.orange)
      .font(.system(size: 48))
  }
}

private struct PermissionTexts: View {
  var body: some View {
    VStack(spacing: 16) {
      Text(LocalizationKey.permissionRequired.localized)
        .font(.title2)
        .fontWeight(.semibold)
        .multilineTextAlignment(.center)

      Text(LocalizationKey.permissionDescription.localized)
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct PermissionButton: View {
  let permissionManager: PermissionManager

  var body: some View {
    Button(action: permissionManager.requestAccessibilityPermission) {
      HStack {
        Image(systemName: "gear")
        Text(LocalizationKey.openSystemPreferences.localized)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(Color.accentColor)
      .foregroundColor(.white)
      .cornerRadius(8)
    }
    .buttonStyle(PlainButtonStyle())
    .padding(.top, 8)
  }
}

private struct QuitButton: View {
  var body: some View {
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
