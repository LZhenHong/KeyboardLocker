import Core
import SwiftUI

@MainActor
class ContentViewState: ObservableObject {
  // MARK: - Published Properties

  @Published var isKeyboardLocked = false
  @Published var selectedTimedLockDuration: CoreConfiguration.Duration = .infinite
  @Published var showTimedLockOptions = false
  @Published var customMinutes: Int = 5

  // MARK: - Dependencies

  var keyboardManager: KeyboardLockManager?
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Computed Properties

  var customMinutesString: Binding<String> {
    Binding<String>(
      get: { String(self.customMinutes) },
      set: { self.customMinutes = Int($0) ?? 5 }
    )
  }

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

  func startTimedLock() {
    lock(with: selectedTimedLockDuration)
  }

  func startTimedLock(with duration: CoreConfiguration.Duration) {
    lock(with: duration)
  }

  func startCustomTimedLock() {
    guard customMinutes > 0 else { return }

    let customDuration = CoreConfiguration.Duration.minutes(customMinutes)
    lock(with: customDuration)
  }

  // MARK: - Private Methods

  private func lock(with duration: CoreConfiguration.Duration) {
    guard let keyboardManager else { return }

    showTimedLockOptions = false
    keyboardManager.lockKeyboard(with: duration)
  }

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
