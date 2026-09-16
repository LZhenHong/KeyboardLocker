import SwiftUI

/// Root of the menu-bar popover: a single surface that swaps between the status page and the
/// settings page, so the user never leaves the popover to change configuration.
///
/// Navigation is a lightweight `@State` enum rather than `NavigationStack`: the popover is a fixed,
/// small surface with no need for a navigation bar or a growing back stack, and a plain crossfade
/// reads better than a push transition inside a bubble.
struct PopoverRootView: View {
  @ObservedObject var store: AppUIStore
  let actions: PopoverActions

  @State private var page: Page = .status

  enum Page {
    case status
    case settings
  }

  var body: some View {
    Group {
      switch page {
      case .status:
        StatusPage(
          store: store,
          actions: actions,
          openSettings: { navigate(to: .settings) }
        )
        .transition(.opacity)

      case .settings:
        SettingsPage(
          store: store,
          actions: actions,
          goBack: { navigate(to: .status) }
        )
        .transition(.opacity)
      }
    }
    .frame(width: 320)
    .animation(.easeInOut(duration: 0.15), value: page)
    .onAppear {
      // The popover is created lazily and shown on demand; recalibrate each time it appears in
      // case a broadcast was missed while it was closed.
      store.reconcile()
    }
  }

  private func navigate(to page: Page) {
    self.page = page
  }
}
