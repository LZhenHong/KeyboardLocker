import Core
import SwiftUI

struct LockControlButtonView: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    HStack(spacing: 8) {
      MainLockButton(state: state)
    }
  }
}

private struct MainLockButton: View {
  @ObservedObject var state: ContentViewState
  @EnvironmentObject private var keyboardManager: KeyboardLockManager

  var body: some View {
    Button(action: toggleLock) {
      HStack {
        Image(systemName: state.isKeyboardLocked ? "lock.open" : "lock")
        Text(lockButtonText)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(state.isKeyboardLocked ? Color.red : Color.green)
      .foregroundColor(.white)
      .cornerRadius(8)
    }
    .buttonStyle(PlainButtonStyle())
  }

  private var lockButtonText: String {
    state.isKeyboardLocked
      ? LocalizationKey.actionUnlock.localized
      : LocalizationKey.actionLock.localized
  }

  private func toggleLock() {
    if state.isKeyboardLocked {
      keyboardManager.unlockKeyboard()
    } else {
      keyboardManager.lockKeyboard()
    }
  }
}

