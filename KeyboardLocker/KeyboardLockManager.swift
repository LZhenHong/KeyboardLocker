import Carbon
import Cocoa
import Foundation
import UserNotifications

/// Core keyboard locking functionality with global hotkey support
class KeyboardLockManager: ObservableObject {
  @Published var isLocked = false

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var globalHotkeyMonitor: Any?

  deinit {
    cleanup()
  }

  init() {
    setupGlobalHotkey()
  }

  /// Clean up resources when object is deallocated
  private func cleanup() {
    unlockKeyboard()
    removeGlobalHotkey()
  }

  func lockKeyboard() {
    guard !isLocked else { return }

    // Verify accessibility permissions are granted
    guard AXIsProcessTrusted() else {
      print("Accessibility permission not granted")
      return
    }

    do {
      // Create event tap for global keyboard monitoring
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap,
          place: .headInsertEventTap,
          options: .defaultTap,
          eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
          callback: { proxy, type, event, refcon in
            Unmanaged<KeyboardLockManager>.fromOpaque(refcon!).takeUnretainedValue().handleKeyEvent(
              proxy: proxy, type: type, event: event
            )
          },
          userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
      else {
        throw NSError(
          domain: "KeyboardLocker", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Failed to create event tap"]
        )
      }

      eventTap = tap
      runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

      guard let runLoopSource = runLoopSource else {
        throw NSError(
          domain: "KeyboardLocker", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Failed to create run loop source"]
        )
      }

      // Attach to current run loop for event processing
      CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)

      isLocked = true
      print("Keyboard locked successfully")

      showNotification(
        title: LocalizationKey.notificationKeyboardLocked.localized,
        body: LocalizationKey.notificationLockedMessage.localized
      )
    } catch {
      print("Failed to lock keyboard: \(error)")
      recoverFromError()
    }
  }

  func unlockKeyboard() {
    guard isLocked else { return }

    // Disable and clean up event tap
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }

    // Remove run loop source
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }

    isLocked = false
    print("Keyboard unlocked successfully")

    showNotification(
      title: LocalizationKey.notificationKeyboardUnlocked.localized,
      body: LocalizationKey.notificationUnlockedMessage.localized
    )
  }

  /// Check if the event matches unlock combination (⌘+⌥+L)
  private func isUnlockCombination(_ event: NSEvent) -> Bool {
    return event.modifierFlags.contains([.command, .option]) && event.keyCode == 37 // L key code
  }

  /// Send notification to user about lock/unlock status
  private func showNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("Failed to send notification: \(error)")
      }
    }
  }

  /// Handle intercepted keyboard events - core locking logic
  private func handleKeyEvent(proxy _: CGEventTapProxy, type _: CGEventType, event: CGEvent)
    -> Unmanaged<CGEvent>?
  {
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Allow unlock combination (⌘+⌥+L) to pass through
    if flags.contains([.maskCommand, .maskAlternate]), keyCode == 37 {
      // Allow this combination and unlock keyboard
      DispatchQueue.main.async {
        self.unlockKeyboard()
      }
      return Unmanaged.passRetained(event)
    }

    // Block all other key events when locked
    return nil
  }

  // MARK: - Global Hotkey Management

  /// Setup global hotkey monitoring for ⌘+⌥+L and ⌘+⌥+⇧+L
  private func setupGlobalHotkey() {
    globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      self?.handleGlobalHotkey(event: event)
    }
    print("Global hotkey monitor setup successfully")
  }

  /// Remove global hotkey monitoring
  private func removeGlobalHotkey() {
    if let monitor = globalHotkeyMonitor {
      NSEvent.removeMonitor(monitor)
      globalHotkeyMonitor = nil
      print("Global hotkey monitor removed")
    }
  }

  /// Handle global hotkey events for lock/unlock
  private func handleGlobalHotkey(event: NSEvent) {
    // Check for ⌘+⌥+L combination
    guard isUnlockCombination(event) else { return }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      if self.isLocked {
        self.unlockKeyboard()
      } else {
        self.lockKeyboard()
      }
    }
  }

  // MARK: - Error Recovery

  /// Attempts to recover from errors by ensuring keyboard is unlocked
  private func recoverFromError() {
    print("Attempting error recovery...")

    // Force cleanup of any existing event taps
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }

    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }

    // Reset state
    isLocked = false
    print("Error recovery completed - keyboard unlocked")

    // Show recovery notification
    showNotification(
      title: "Keyboard Locker Recovery",
      body: "Application recovered from an error. Keyboard has been unlocked."
    )
  }
}
