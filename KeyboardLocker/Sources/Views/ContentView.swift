import Core
import SwiftUI

struct ContentView: View {
  @StateObject private var viewState = ContentViewState()
  @EnvironmentObject var permissionManager: PermissionManager
  @EnvironmentObject var keyboardManager: KeyboardLockManager

  var body: some View {
    NavigationStack {
      if permissionManager.hasAccessibilityPermission {
        MainContentView(state: viewState)
      } else {
        PermissionRequiredView(permissionManager: permissionManager)
      }
    }
    .frame(width: .viewWidth)
    .background(Color(NSColor.windowBackgroundColor))
    .onAppear(perform: setupInitialState)
    .onDisappear(perform: viewState.cleanup)
  }

  private func setupInitialState() {
    permissionManager.checkAllPermissions()
    viewState.setup(with: keyboardManager)
  }
}

private struct MainContentView: View {
  @ObservedObject var state: ContentViewState
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    VStack(spacing: 16) {
      AppTitleHeaderView()

      VStack(spacing: 16) {
        if let keyboardManager = state.keyboardManager {
          StatusSectionView(
            isKeyboardLocked: state.isKeyboardLocked,
            keyboardManager: keyboardManager
          )

          LockControlButtonView(
            state: state,
            keyboardManager: keyboardManager
          )

          QuickActionsView(keyboardManager: keyboardManager)
        }
      }
      .padding(.horizontal, 16)

      BottomActionsView()
    }
  }
}
