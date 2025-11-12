import Core
import SwiftUI

struct PermissionRequiredView: View {
  var body: some View {
    VStack(spacing: 20) {
      AppTitleHeaderView()
      PermissionContent()
      Spacer()

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
}

private struct PermissionContent: View {
  @EnvironmentObject private var permissionManager: PermissionManager

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.orange)
        .font(.system(size: 48))

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
    .padding(.horizontal, 16)
  }
}
