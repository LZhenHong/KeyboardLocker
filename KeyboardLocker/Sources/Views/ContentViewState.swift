import Core
import SwiftUI

@MainActor
class ContentViewState: ObservableObject {
  // MARK: - Published Properties

  @Published var isKeyboardLocked = false
  @Published var selectedTimedLockDuration: CoreConfiguration.Duration = .infinite
  @Published var showTimedLockOptions = false
  @Published var customMinutes: Int = 5

  // MARK: - Private Properties

  private var lockDurationTimer: Timer?
  var keyboardManager: KeyboardLockManager?

  // MARK: - Computed Properties

  var customMinutesString: Binding<String> {
    Binding<String>(
      get: { String(self.customMinutes) },
      set: { self.customMinutes = Int($0) ?? 5 }
    )
  }

  // MARK: - Public Methods

  func configure(with keyboardManager: KeyboardLockManager) {
    self.keyboardManager = keyboardManager
    isKeyboardLocked = keyboardManager.isLocked
  }

  func handleLockStateChange(_ locked: Bool) {
    isKeyboardLocked = locked
    setupLockDurationTimer()
  }

  func startTimedLock() {
    lock(with: selectedTimedLockDuration)
  }

  func startCustomTimedLock() {
    guard customMinutes > 0 else { return }

    let customDuration = CoreConfiguration.Duration.minutes(customMinutes)
    lock(with: customDuration)
  }

  private func lock(with duration: CoreConfiguration.Duration) {
    guard let keyboardManager else { return }

    showTimedLockOptions = false
    keyboardManager.lockKeyboard(with: duration)
  }

  func cleanup() {
    lockDurationTimer?.invalidate()
    lockDurationTimer = nil
  }

  // MARK: - Private Methods

  private func setupLockDurationTimer() {
    cleanup()
    guard isKeyboardLocked else { return }

    lockDurationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        self?.objectWillChange.send()
      }
    }
  }
}
