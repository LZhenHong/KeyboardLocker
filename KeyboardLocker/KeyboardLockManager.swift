import Carbon
import Cocoa
import Foundation
import UserNotifications

/// Core keyboard locking functionality with comprehensive input blocking
class KeyboardLockManager: ObservableObject {
  @Published var isLocked = false

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var globalHotkeyMonitor: Any?
  private var functionKeyMonitor: Any?
  private var comprehensiveMonitor: Any? // Additional comprehensive monitoring

  init() {
    setupGlobalHotkey()
  }

  deinit {
    cleanup()
  }

  /// Clean up resources when object is deallocated
  private func cleanup() {
    unlockKeyboard()
    removeGlobalHotkey()
    removeFunctionKeyMonitor()
    removeComprehensiveMonitor()
  }

  func lockKeyboard() {
    guard !isLocked else { return }

    // Verify accessibility permissions are granted
    guard AXIsProcessTrusted() else {
      print("Accessibility permission not granted")
      return
    }

    do {
      // Create the most comprehensive event mask possible
      // Include ALL possible event types that could involve keyboard input
      let eventTypes: [CGEventType] = [
        .keyDown,
        .keyUp,
        .flagsChanged,
        .scrollWheel, // Some scroll wheels can trigger shortcuts
        .tabletPointer,
        .tabletProximity,
        .otherMouseDown,
        .otherMouseUp,
        .otherMouseDragged,
      ]

      // Build comprehensive event mask
      var eventMask: CGEventMask = 0
      for eventType in eventTypes {
        eventMask |= CGEventMask(1 << eventType.rawValue)
      }

      // Also include system-defined events mask manually
      eventMask |= CGEventMask(1 << 14) // NX_SYSDEFINED

      // Create event tap for global input monitoring with highest possible interception level
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap, // Intercept at session level
          place: .headInsertEventTap, // Insert at the head for maximum priority
          options: .defaultTap, // Default options for maximum compatibility
          eventsOfInterest: eventMask,
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

      // Setup additional function key monitoring
      setupFunctionKeyMonitor()

      // Setup comprehensive backup monitoring
      setupComprehensiveMonitor()

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

    // Remove function key monitor
    removeFunctionKeyMonitor()

    // Remove comprehensive monitor
    removeComprehensiveMonitor()

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

  /// Handle intercepted events - comprehensive input blocking logic
  private func handleKeyEvent(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Handle different event types comprehensively
    switch type {
    case .keyDown, .keyUp:
      // Allow unlock combination (⌘+⌥+L) to pass through - only on keyDown
      if type == .keyDown, flags.contains([.maskCommand, .maskAlternate]), keyCode == 37 {
        // Allow this combination and unlock keyboard
        DispatchQueue.main.async {
          self.unlockKeyboard()
        }
        return Unmanaged.passRetained(event)
      }

      // Block ALL other keyboard events when locked
      print("Blocked keyboard event: type=\(type.rawValue), keyCode=\(keyCode)")
      return nil

    case .flagsChanged:
      // Block ALL modifier key changes to prevent any shortcuts
      print("Blocked modifier key change: flags=\(flags)")
      return nil

    case .scrollWheel:
      // Block scroll wheel events that might trigger shortcuts (like zoom)
      let scrollingDeltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
      let scrollingDeltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)

      // Only block if there are modifier keys pressed (likely shortcuts)
      if !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty {
        print(
          "Blocked scroll shortcut: deltaX=\(scrollingDeltaX), deltaY=\(scrollingDeltaY), flags=\(flags)"
        )
        return nil
      }

      // Allow normal scrolling
      return Unmanaged.passRetained(event)

    case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
      // Block additional mouse buttons that might trigger shortcuts
      let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

      // Block if modifier keys are pressed (likely shortcuts)
      if !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty {
        print("Blocked mouse shortcut: button=\(buttonNumber), flags=\(flags)")
        return nil
      }

      // Allow normal mouse events
      return Unmanaged.passRetained(event)

    case .tabletPointer, .tabletProximity:
      // Block tablet events that might have shortcut functions
      if !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty {
        print("Blocked tablet shortcut event")
        return nil
      }

      // Allow normal tablet events
      return Unmanaged.passRetained(event)

    default:
      // For any unknown event types, check if they have modifier keys
      if type.rawValue == 14 { // NX_SYSDEFINED - system defined events
        print("Blocked system-defined event")
        return nil // Block all system-defined events (media keys, function keys, etc.)
      }

      // Block other events if they have modifier keys (potential shortcuts)
      if !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty {
        print("Blocked unknown event with modifiers: type=\(type.rawValue), flags=\(flags)")
        return nil
      }

      // Allow events without modifier keys
      return Unmanaged.passRetained(event)
    }
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

  /// Setup comprehensive function key and system event monitoring
  private func setupFunctionKeyMonitor() {
    functionKeyMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [
        .keyDown, .keyUp, .systemDefined, .flagsChanged, .scrollWheel, .rightMouseDown,
        .rightMouseUp, .otherMouseDown, .otherMouseUp,
      ]
    ) { [weak self] event in
      self?.handleFunctionKeyEvent(event: event)
    }
    print("Comprehensive function key and system event monitor setup successfully")
  }

  /// Remove function key monitoring
  private func removeFunctionKeyMonitor() {
    if let monitor = functionKeyMonitor {
      NSEvent.removeMonitor(monitor)
      functionKeyMonitor = nil
      print("Function key monitor removed")
    }
  }

  /// Handle function key events and additional input types (F1-F12, media keys, etc.)
  private func handleFunctionKeyEvent(event: NSEvent) {
    guard isLocked else { return }

    let keyCode = event.keyCode
    let modifierFlags = event.modifierFlags

    // Block function keys (F1-F12) and their variants
    let functionKeyCodes: Set<UInt16> = [
      122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1-F12
      119, 114, 115, 116, 117, // Additional function keys
      113, 115, 116, 130, // Media keys and volume controls
    ]

    // Block based on event type
    switch event.type {
    case .keyDown, .keyUp:
      if functionKeyCodes.contains(keyCode) {
        print("NSEvent: Blocked function/media key: F\(keyCode)")
        // Note: NSEvent global monitors cannot prevent the event, but we log it
      }

      // Block any key event when locked (backup to CGEvent tap)
      if event.type == .keyDown {
        print("NSEvent: Blocked additional key down: \(keyCode)")
      }

    case .systemDefined:
      // Block ALL system-defined events (media keys, volume, brightness, etc.)
      print("NSEvent: Blocked system-defined event: subtype=\(event.subtype)")

    case .flagsChanged:
      // Block modifier key changes
      print("NSEvent: Blocked modifier change: \(modifierFlags)")

    case .scrollWheel:
      // Block scroll wheel with modifiers (zoom shortcuts, etc.)
      if !modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
        print("NSEvent: Blocked scroll with modifiers")
      }

    case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
      // Block right-click and other mouse buttons with modifiers
      if !modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
        print("NSEvent: Blocked mouse event with modifiers")
      }

    default:
      break
    }
  }

  /// Setup comprehensive backup monitoring for any missed events
  private func setupComprehensiveMonitor() {
    // Monitor ALL possible NSEvent types as a backup layer
    let allEventTypes: NSEvent.EventTypeMask = [
      .keyDown, .keyUp, .flagsChanged,
      .leftMouseDown, .leftMouseUp, .leftMouseDragged,
      .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .otherMouseDown, .otherMouseUp, .otherMouseDragged,
      .mouseEntered, .mouseExited, .mouseMoved,
      .scrollWheel, .tabletPoint, .tabletProximity,
      .systemDefined, .applicationDefined, .periodic,
      .cursorUpdate, .rotate, .beginGesture, .endGesture,
      .magnify, .swipe, .smartMagnify,
      .pressure, .directTouch, .changeMode,
    ]

    comprehensiveMonitor = NSEvent.addGlobalMonitorForEvents(matching: allEventTypes) {
      [weak self] event in
      self?.handleComprehensiveEvent(event: event)
    }
    print("Comprehensive backup monitor setup successfully")
  }

  /// Remove comprehensive monitoring
  private func removeComprehensiveMonitor() {
    if let monitor = comprehensiveMonitor {
      NSEvent.removeMonitor(monitor)
      comprehensiveMonitor = nil
      print("Comprehensive monitor removed")
    }
  }

  /// Handle any events that might have been missed by primary monitoring
  private func handleComprehensiveEvent(event: NSEvent) {
    guard isLocked else { return }

    // Log any input events that occur while locked for debugging
    switch event.type {
    case .keyDown, .keyUp, .flagsChanged:
      print("BACKUP: Detected keyboard event: \(event.type) - keyCode: \(event.keyCode)")

    case .systemDefined:
      print("BACKUP: Detected system event: subtype \(event.subtype)")

    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown,
         .otherMouseUp:
      if !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
        print("BACKUP: Detected mouse shortcut attempt")
      }

    case .scrollWheel:
      if !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
        print("BACKUP: Detected scroll shortcut attempt")
      }

    case .swipe, .magnify, .rotate, .smartMagnify:
      print("BACKUP: Detected gesture that might trigger shortcuts")

    default:
      if !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
        print("BACKUP: Detected event with modifiers: \(event.type)")
      }
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
      title: LocalizationKey.errorRecoveryTitle.localized,
      body: LocalizationKey.errorRecoveryMessage.localized
    )
  }
}
