import Core
import SwiftUI

struct LockControlButtonView: View {
  @ObservedObject var state: ContentViewState
  let keyboardManager: KeyboardLockManager

  var body: some View {
    HStack(spacing: 8) {
      MainLockButton(state: state, keyboardManager: keyboardManager)

      if !state.isKeyboardLocked {
        TimedLockOptionsButton(state: state)
      }
    }
  }
}

private struct MainLockButton: View {
  @ObservedObject var state: ContentViewState
  let keyboardManager: KeyboardLockManager

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

private struct TimedLockOptionsButton: View {
  @ObservedObject var state: ContentViewState

  var body: some View {
    Button(action: { state.showTimedLockOptions.toggle() }) {
      Image(systemName: "info.circle")
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(.accentColor)
        .frame(width: 44, height: 44)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(22)
    }
    .buttonStyle(PlainButtonStyle())
    .popover(isPresented: $state.showTimedLockOptions, arrowEdge: .bottom) {
      TimedLockControlsView(state: state)
        .frame(width: 280)
        .padding()
    }
  }
}
