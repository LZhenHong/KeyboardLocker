import AppKit
import ApplicationServices
import Carbon

/// User activity monitor for tracking keyboard and mouse activity
/// Used to implement proper auto-lock behavior that only starts counting when user stops activity
public class UserActivityMonitor {
  // MARK: - Singleton

  public static let shared = UserActivityMonitor()

  // MARK: - Properties

  private var activityEventTap: CFMachPort?
  private var activityRunLoopSource: CFRunLoopSource?
  private var lastActivityTime: Date = .init()
  private var autoLockTimer: Timer?

  /// Callback when auto-lock should be triggered
  public var onAutoLockTriggered: (() -> Void)?

  /// Current auto-lock duration in seconds (0 = disabled)
  private var autoLockDuration: TimeInterval = 0

  /// Whether auto-lock is currently enabled
  public var isAutoLockEnabled: Bool {
    autoLockDuration > 0
  }

  /// Time since last user activity
  public var timeSinceLastActivity: TimeInterval {
    Date().timeIntervalSince(lastActivityTime)
  }

  // MARK: - Initialization

  private init() {}

  deinit {
    stopMonitoring()
  }

  // MARK: - Public Methods

  /// Start monitoring user activity
  public func startMonitoring() {
    guard activityEventTap == nil else {
      print("⚠️ Activity monitoring already started")
      return
    }

    do {
      try createActivityEventTap()
      resetActivityTimer()
      print("✅ User activity monitoring started")
    } catch {
      print("❌ Failed to start activity monitoring: \(error)")
    }
  }

  /// Stop monitoring user activity
  public func stopMonitoring() {
    destroyActivityEventTap()
    stopAutoLockTimer()
    print("🛑 User activity monitoring stopped")
  }

  /// Reset the activity timer (called when user is active)
  public func resetActivityTimer() {
    lastActivityTime = Date()
    updateAutoLockTimer()
    print("🔄 User activity detected, timer reset")
  }

  /// Enable auto-lock with specified duration
  /// - Parameter seconds: Duration in seconds (0 to disable)
  public func enableAutoLock(seconds: TimeInterval) {
    if seconds > 0 {
      print("✅ Auto-lock enabled: \(seconds) seconds")

      autoLockDuration = seconds
      updateAutoLockTimer()
    } else {
      print("❌ Auto-lock disabled")
      stopAutoLockTimer()
    }
  }

  /// Disable auto-lock
  public func disableAutoLock() {
    autoLockDuration = 0
    stopAutoLockTimer()
  }

  // MARK: - Private Methods

  private func createActivityEventTap() throws {
    // Check accessibility permission using PermissionHelper
    guard PermissionHelper.hasAccessibilityPermission() else {
      throw UserActivityError.permissionDenied
    }

    // Create event mask for all user activity
    let keyEvents = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    let mouseEvents = (1 << CGEventType.leftMouseDown.rawValue) |
      (1 << CGEventType.leftMouseUp.rawValue) |
      (1 << CGEventType.rightMouseDown.rawValue) |
      (1 << CGEventType.rightMouseUp.rawValue) |
      (1 << CGEventType.otherMouseDown.rawValue) |
      (1 << CGEventType.otherMouseUp.rawValue)
    let motionEvents = (1 << CGEventType.mouseMoved.rawValue) |
      (1 << CGEventType.leftMouseDragged.rawValue) |
      (1 << CGEventType.rightMouseDragged.rawValue) |
      (1 << CGEventType.scrollWheel.rawValue)

    let eventMask = keyEvents | mouseEvents | motionEvents

    // Create event tap
    activityEventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly, // Only listen, don't block events
      eventsOfInterest: CGEventMask(eventMask),
      callback: { _, _, event, refcon in
        guard let refcon else {
          return Unmanaged.passUnretained(event)
        }
        let monitor = Unmanaged<UserActivityMonitor>.fromOpaque(refcon).takeUnretainedValue()
        monitor.handleActivityEvent(event)
        return Unmanaged.passUnretained(event)
      },
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    )

    guard let eventTap = activityEventTap else {
      throw UserActivityError.eventTapCreationFailed
    }

    // Create run loop source
    activityRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    guard let runLoopSource = activityRunLoopSource else {
      CFMachPortInvalidate(eventTap)
      activityEventTap = nil
      throw UserActivityError.runLoopSourceCreationFailed
    }

    // Add to run loop
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  private func destroyActivityEventTap() {
    if let eventTap = activityEventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
      activityEventTap = nil
    }

    if let runLoopSource = activityRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      activityRunLoopSource = nil
    }
  }

  private func handleActivityEvent(_: CGEvent) {
    // Reset activity timer on any user input
    resetActivityTimer()
  }

  private func updateAutoLockTimer() {
    stopAutoLockTimer()

    guard autoLockDuration > 0 else {
      return
    }

    // Start new timer
    autoLockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.checkAutoLock()
    }
  }

  private func stopAutoLockTimer() {
    autoLockTimer?.invalidate()
    autoLockTimer = nil
  }

  private func checkAutoLock() {
    guard autoLockDuration > 0 else {
      stopAutoLockTimer()
      return
    }

    let timeSinceActivity = Date().timeIntervalSince(lastActivityTime)

    if timeSinceActivity >= autoLockDuration {
      // Trigger auto-lock
      stopAutoLockTimer()
      onAutoLockTriggered?()
      print("🔒 Auto-lock triggered after \(autoLockDuration) seconds of inactivity")
    }
  }
}

// MARK: - Error Types

public enum UserActivityError: Error, LocalizedError {
  case permissionDenied
  case eventTapCreationFailed
  case runLoopSourceCreationFailed

  public var errorDescription: String? {
    switch self {
    case .permissionDenied:
      "Accessibility permission required for activity monitoring"
    case .eventTapCreationFailed:
      "Failed to create activity event tap"
    case .runLoopSourceCreationFailed:
      "Failed to create run loop source for activity monitoring"
    }
  }
}
