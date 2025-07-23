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
      VStack(alignment: .leading, spacing: 6) {
        Text(LocalizationKey.aboutFeatures.localized)
          .font(.headline)

        VStack(alignment: .leading, spacing: 4) {
          FeatureRow(icon: "lock", text: LocalizationKey.aboutFeatureLock.localized)
          FeatureRow(icon: "keyboard", text: LocalizationKey.aboutFeatureShortcut.localized)
          FeatureRow(icon: "timer", text: LocalizationKey.aboutFeatureAutoLock.localized)
        }
      }

      Spacer()

      // Copyright information from Info.plist
      Text(Bundle.main.copyright)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding()
    .navigationTitle(LocalizationKey.aboutTitle.localized)
    .frame(minWidth: 320, maxWidth: 400, minHeight: 300)
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
