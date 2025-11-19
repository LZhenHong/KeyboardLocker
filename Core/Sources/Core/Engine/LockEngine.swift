import AppKit
import CoreGraphics
import Foundation

// Global callback for CGEventTap
private func eventTapCallback(proxy _: CGEventTapProxy, type _: CGEventType, event _: CGEvent, refcon _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
  // In a real implementation, we might check for a specific "Unlock" key combination here.
  // For now, we block all keyboard events when locked.
  // Returning nil consumes the event.
  nil
}

public class LockEngine {
  public static let shared = LockEngine()

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  // Thread-safe property access could be improved, but for this MVP we assume main thread usage for XPC handling
  public private(set) var isLocked = false

  private init() {}

  public func lock() throws {
    guard !isLocked else { return }

    let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(eventMask),
      callback: eventTapCallback,
      userInfo: nil
    ) else {
      throw NSError(domain: "LockEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create event tap. Check Accessibility permissions."])
    }

    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    isLocked = true
    print("LockEngine: Locked")
  }

  public func unlock() {
    guard isLocked else { return }

    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      // We don't necessarily need to destroy the tap, but it's cleaner to do so if we want to fully reset
      if let source = runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        runLoopSource = nil
      }
      eventTap = nil
    }

    isLocked = false
    print("LockEngine: Unlocked")
  }
}
