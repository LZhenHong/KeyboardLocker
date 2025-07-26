import Carbon
import Cocoa
import Foundation
import SwiftUI

/// UI-focused keyboard lock manager with full functionality
class KeyboardLockManager: ObservableObject, KeyboardLockManaging {
  @Published var isLocked = false

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var autoLockTimer: Timer?
  private var lastActivityTime = Date()
  private var lockStartTime: Date?

  // Use protocol to reduce coupling
  private let notificationManager: NotificationManaging
  private let configuration: AppConfiguration

  // Constants for hotkey
  private let unlockKeyCode: UInt16 = 37 // 'L' key
  private let unlockModifiers: UInt32 = .init(cmdKey | optionKey) // Cmd+Option

  init(
    notificationManager: NotificationManaging = NotificationManager.shared,
    configuration: AppConfiguration = AppConfiguration.shared
  ) {
    self.notificationManager = notificationManager
    self.configuration = configuration
    setupActivityMonitoring()
  }

  deinit {
    cleanup()
  }

  /// Clean up resources when object is deallocated
  private func cleanup() {
    unlockKeyboard()
    stopAutoLock()
  }

  // MARK: - Public Interface

  func lockKeyboard() {
    guard !isLocked else { return }

    do {
      try performLockKeyboard()
    } catch {
      print("Failed to lock keyboard: \(error.localizedDescription)")
    }
  }

  private func performLockKeyboard() throws {
    // Verify accessibility permissions are granted
    guard AXIsProcessTrusted() else {
      throw KeyboardLockerError.accessibilityPermissionDenied
    }

    // Use safe event type factory to create event mask
    let eventMask = EventTypeFactory.createEventMask()

    // Create event tap for intercepting input events
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: { proxy, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<KeyboardLockManager>.fromOpaque(refcon).takeUnretainedValue()
        return manager.handleKeyEvent(proxy: proxy, type: type, event: event)
      },
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    )
    else {
      throw KeyboardLockerError.eventTapCreationFailed
    }

    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

    guard let runLoopSource = runLoopSource else {
      throw KeyboardLockerError.runLoopSourceCreationFailed
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    isLocked = true
    lockStartTime = Date()
    print("Keyboard locked successfully")

    // Send notification to user
    notificationManager.sendNotificationIfEnabled(
      .keyboardLocked,
      showNotifications: configuration.showNotifications
    )

    print("🔒 Keyboard locked successfully")
  }

  func unlockKeyboard() {
    guard isLocked else { return }

    // Disable event tap
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }

    // Remove run loop source
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    }

    // Invalidate and clean up
    if let eventTap = eventTap {
      CFMachPortInvalidate(eventTap)
    }

    eventTap = nil
    runLoopSource = nil
    isLocked = false
    lockStartTime = nil

    // Send notification to user
    notificationManager.sendNotificationIfEnabled(
      .keyboardUnlocked,
      showNotifications: configuration.showNotifications
    )

    print("🔓 Keyboard unlocked successfully")
  }

  func toggleLock() {
    if isLocked {
      unlockKeyboard()
    } else {
      lockKeyboard()
    }
  }

  // MARK: - Auto-Lock Management

  func startAutoLock() {
    guard !configuration.isAutoLockEnabled else {
      print("Auto-lock is already enabled")
      return
    }

    // Update configuration to enable auto-lock
    configuration.autoLockDuration = max(configuration.autoLockDuration, 15) // Minimum 15 minutes
    scheduleAutoLock()
    print("Auto-lock enabled with \(configuration.autoLockDuration) minutes duration")
  }

  func stopAutoLock() {
    // 禁用自动锁定
    configuration.autoLockDuration = 0

    // 停止并清理计时器
    autoLockTimer?.invalidate()
    autoLockTimer = nil

    print("Auto-lock disabled")
  }

  func toggleAutoLock() {
    if configuration.isAutoLockEnabled {
      stopAutoLock()
    } else {
      startAutoLock()
    }
  }

  func updateAutoLockSettings() {
    if configuration.isAutoLockEnabled {
      // 自动锁定已启用，重新调度计时器
      scheduleAutoLock()
      print("Auto-lock settings updated: enabled with \(configuration.autoLockDuration) minutes")
    } else {
      // 自动锁定已禁用，停止计时器
      autoLockTimer?.invalidate()
      autoLockTimer = nil
      print("Auto-lock settings updated: disabled")
    }
  }

  private func setupActivityMonitoring() {
    // Monitor global events for activity detection
    NSEvent.addGlobalMonitorForEvents(matching: [
      .keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved,
    ]) { _ in
      self.lastActivityTime = Date()
      // 每次用户有活动时，重新调度自动锁定计时器
      if self.configuration.isAutoLockEnabled, !self.isLocked {
        self.scheduleAutoLock()
      }
    }

    // 初始化时如果启用了自动锁定，开始计时
    if configuration.isAutoLockEnabled {
      scheduleAutoLock()
    }
  }

  private func scheduleAutoLock() {
    // 停止现有的计时器
    autoLockTimer?.invalidate()

    // 如果自动锁定被禁用，不设置新的计时器
    guard configuration.isAutoLockEnabled else {
      autoLockTimer = nil
      return
    }

    // 设置新的计时器，从现在开始计算指定的时间
    autoLockTimer = Timer.scheduledTimer(withTimeInterval: configuration.autoLockDurationInSeconds, repeats: false) { _ in
      DispatchQueue.main.async {
        // 双重检查：确保自动锁定仍然启用且键盘未锁定
        if self.configuration.isAutoLockEnabled, !self.isLocked {
          print("Auto-lock triggered after \(self.configuration.autoLockDuration) minutes of inactivity")
          self.lockKeyboard()
        }
      }
    }

    print("Auto-lock timer scheduled for \(configuration.autoLockDuration) minutes from now")
  }

  // MARK: - Event Handling

  /// Handle intercepted events - comprehensive input blocking logic
  private func handleKeyEvent(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    // Handle tap disabled case
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap = eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return nil
    }

    // If not locked, allow all events
    guard isLocked else {
      return Unmanaged.passUnretained(event)
    }

    let flags = SafeEventHandler.getFlags(from: event)
    let keyCode = SafeEventHandler.getKeycode(from: event) ?? 0

    // Handle different event types comprehensively
    switch type {
    case .keyDown, .keyUp:
      return handleKeyboardEvent(type: type, event: event, keyCode: keyCode)

    case .flagsChanged:
      return handleModifierEvent(flags: flags)

    default:
      return handleOtherEvent(type: type, event: event, flags: flags)
    }
  }

  private func handleKeyboardEvent(type: CGEventType, event: CGEvent, keyCode: Int64) -> Unmanaged<
    CGEvent
  >? {
    // Allow unlock combination (⌘+⌥+L) to pass through - only on keyDown
    if type == .keyDown, isUnlockHotkey(event: event) {
      DispatchQueue.main.async {
        self.unlockKeyboard()
      }
      return nil // Consume this event, don't pass to system
    }

    // Block ALL other keyboard events when locked
    print("Blocked keyboard event: type=\(type.rawValue), keyCode=\(keyCode)")
    return nil
  }

  private func handleModifierEvent(flags: CGEventFlags) -> Unmanaged<CGEvent>? {
    // Block ALL modifier key changes to prevent any shortcuts
    print("Blocked modifier key change: flags=\(flags)")
    return nil
  }

  private func handleOtherEvent(type: CGEventType, event: CGEvent, flags: CGEventFlags) -> Unmanaged<CGEvent>? {
    // Check if this is a system-defined event (function keys, etc.)
    if EventTypeFactory.isSystemDefinedEvent(type) {
      // This is the key for function keys! Block ALL system-defined events
      if let subtype = EventTypeFactory.getSystemDefinedSubtype(from: event) {
        print("Blocked system-defined event: subtype=\(subtype)")
      } else {
        print("Blocked system-defined event: unable to get subtype")
      }
      // Directly block all system-defined events, including volume, brightness, and other function keys
      return nil
    }

    // Block unknown event types with modifier keys
    if SafeEventHandler.hasModifiers(event, [.maskCommand, .maskAlternate, .maskControl, .maskShift]) {
      print("Blocked unknown event with modifiers: type=\(type.rawValue), flags=\(flags)")
      return nil
    }

    // Allow events without modifier keys
    return Unmanaged.passUnretained(event)
  }

  private func isUnlockHotkey(event: CGEvent) -> Bool {
    let flags = SafeEventHandler.getFlags(from: event)
    let keyCode = SafeEventHandler.getKeycode(from: event) ?? 0

    // Check for configured unlock hotkey (default: Cmd + Option + L)
    let expectedModifiers = unlockModifiers
    let expectedKeyCode = unlockKeyCode

    var hasRequiredModifiers = true

    if expectedModifiers & UInt32(cmdKey) != 0 {
      hasRequiredModifiers = hasRequiredModifiers && flags.contains(.maskCommand)
    }
    if expectedModifiers & UInt32(optionKey) != 0 {
      hasRequiredModifiers = hasRequiredModifiers && flags.contains(.maskAlternate)
    }
    if expectedModifiers & UInt32(controlKey) != 0 {
      hasRequiredModifiers = hasRequiredModifiers && flags.contains(.maskControl)
    }
    if expectedModifiers & UInt32(shiftKey) != 0 {
      hasRequiredModifiers = hasRequiredModifiers && flags.contains(.maskShift)
    }

    return hasRequiredModifiers && UInt16(keyCode) == expectedKeyCode
  }

  // MARK: - Hotkey Management

  func updateUnlockHotkey(keyCode _: UInt16, modifiers _: UInt32) {
    // Hotkeys are now fixed as constants since they are standard
    print("Unlock hotkey is fixed: Cmd+Option+L (keyCode=37, modifiers=\(unlockModifiers))")
  }

  // MARK: - Utility Methods

  func getLockDurationString() -> String? {
    guard let lockStartTime = lockStartTime, isLocked else {
      return nil
    }

    let duration = Date().timeIntervalSince(lockStartTime)
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60

    if minutes > 0 {
      return String(format: "%dm %ds", minutes, seconds)
    } else {
      return String(format: "%ds", seconds)
    }
  }

  func forceCleanup() {
    unlockKeyboard()
    stopAutoLock()
  }
}
