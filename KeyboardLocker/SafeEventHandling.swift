import CoreGraphics
import Foundation

/// Safe factory for creating CGEventType instances and handling system events
enum EventTypeFactory {
  /// System-defined event type (NX_SYSDEFINED)
  static let systemDefinedEventType: CGEventType? = CGEventType(rawValue: 14)

  /// System-defined event subtype field
  static let systemDefinedSubtypeField: CGEventField? = CGEventField(rawValue: 2)

  /// Get all supported event types for keyboard monitoring
  /// - Returns: Array of valid CGEventType instances
  static func getSupportedEventTypes() -> [CGEventType] {
    var eventTypes: [CGEventType] = [
      .keyDown,
      .keyUp,
      .flagsChanged,
    ]

    // Safely add system-defined events if available
    if let systemDefined = systemDefinedEventType {
      eventTypes.append(systemDefined)
    }

    return eventTypes
  }

  /// Create event mask from supported event types
  /// - Returns: CGEventMask for all supported events
  static func createEventMask() -> CGEventMask {
    let eventTypes = getSupportedEventTypes()
    var eventMask: CGEventMask = 0

    for eventType in eventTypes {
      eventMask |= CGEventMask(1 << eventType.rawValue)
    }

    return eventMask
  }

  /// Check if an event type is a system-defined event
  /// - Parameter eventType: The event type to check
  /// - Returns: True if this is a system-defined event
  static func isSystemDefinedEvent(_ eventType: CGEventType) -> Bool {
    guard let systemDefined = systemDefinedEventType else { return false }
    return eventType.rawValue == systemDefined.rawValue
  }

  /// Get system-defined event subtype safely
  /// - Parameter event: The CGEvent to extract subtype from
  /// - Returns: Subtype value if available, nil otherwise
  static func getSystemDefinedSubtype(from event: CGEvent) -> Int64? {
    guard let subtypeField = systemDefinedSubtypeField else { return nil }
    return event.getIntegerValueField(subtypeField)
  }
}

/// Safe wrapper for CGEvent operations
enum SafeEventHandler {
  /// Safely get keyboard event keycode
  /// - Parameter event: The CGEvent to extract keycode from
  /// - Returns: Keycode value if available, nil otherwise
  static func getKeycode(from event: CGEvent) -> Int64? {
    return event.getIntegerValueField(.keyboardEventKeycode)
  }

  /// Safely get event flags
  /// - Parameter event: The CGEvent to extract flags from
  /// - Returns: CGEventFlags for the event
  static func getFlags(from event: CGEvent) -> CGEventFlags {
    return event.flags
  }

  /// Check if event has specific modifier flags
  /// - Parameters:
  ///   - event: The CGEvent to check
  ///   - modifiers: Array of modifier flags to check for
  /// - Returns: True if event has any of the specified modifiers
  static func hasModifiers(_ event: CGEvent, _ modifiers: [CGEventFlags]) -> Bool {
    let flags = getFlags(from: event)
    return !flags.intersection(CGEventFlags(modifiers)).isEmpty
  }
}
