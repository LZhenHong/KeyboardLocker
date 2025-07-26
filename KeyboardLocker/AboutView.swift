import AppKit
import SwiftUI

struct AboutView: View {
  var body: some View {
    VStack(spacing: 12) {
      // App icon and name
      VStack(spacing: 6) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 100, height: 100)

        Text(LocalizationKey.appTitle.localized)
          .font(.title)
          .fontWeight(.bold)

        Text(Bundle.main.localizedVersionString)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Divider()

      // Core features only
      VStack(alignment: .leading, spacing: 15) {
        Text(LocalizationKey.aboutFeatures.localized)
          .font(.headline)

        VStack(alignment: .leading, spacing: 5) {
          FeatureRow(icon: "lock", text: LocalizationKey.aboutFeatureLock.localized)
          FeatureRow(icon: "keyboard", text: LocalizationKey.aboutFeatureShortcut.localized)
          FeatureRow(icon: "timer", text: LocalizationKey.aboutFeatureAutoLock.localized)
          FeatureRow(icon: "bell", text: LocalizationKey.aboutFeatureNotifications.localized)
        }
      }

      Divider()

      // GitHub link
      Button(action: {
        openGitHubRepository()
      }) {
        HStack {
          Image(systemName: "link.circle.fill")
            .foregroundColor(.blue)
          Text(LocalizationKey.aboutGitHub.localized)
            .foregroundColor(.blue)
        }
        .font(.body)
      }
      .buttonStyle(PlainButtonStyle())
      .onHover { _ in
        NSCursor.pointingHand.set()
      }

      // Copyright information from Info.plist
      Text(Bundle.main.copyright)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding()
    .navigationTitle(LocalizationKey.aboutTitle.localized)
    .frame(width: 300)
  }

  // MARK: - Private Methods

  private func openGitHubRepository() {
    if let url = URL(string: "https://github.com/LZhenHong/KeyboardLocker") {
      NSWorkspace.shared.open(url)
    }
  }
}

struct FeatureRow: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .foregroundColor(.blue)
        .frame(width: 16)

      Text(text)
        .font(.body)
        .foregroundColor(.primary)
    }
  }
}

#Preview {
  NavigationStack {
    AboutView()
  }
}
