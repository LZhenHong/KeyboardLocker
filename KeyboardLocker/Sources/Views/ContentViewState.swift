import Core
import SwiftUI

@MainActor
class ContentViewState: ObservableObject {
  // MARK: - Published Properties

  @Published var isKeyboardLocked = false

  // MARK: - Dependencies

  var keyboardManager: KeyboardLockManager?
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Lifecycle Methods

  func setup(with keyboardManager: KeyboardLockManager) {
    self.keyboardManager = keyboardManager
    setupSubscriptions()
    syncInitialState()
  }

  func cleanup() {
    cancellables.removeAll()
  }

  // MARK: - Public Methods

  private func setupSubscriptions() {
    guard let keyboardManager else { return }

    // Subscribe to lock state changes
    keyboardManager.$isLocked
      .receive(on: DispatchQueue.main)
      .sink { [weak self] isLocked in
        self?.handleLockStateChange(isLocked)
      }
      .store(in: &cancellables)
  }

  private func syncInitialState() {
    handleLockStateChange(keyboardManager?.isLocked ?? false)
  }

  private func handleLockStateChange(_ locked: Bool) {
    isKeyboardLocked = locked
  }
}
