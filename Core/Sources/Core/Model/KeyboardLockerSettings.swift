import CoreGraphics
import Foundation

/// Keyboard lock settings shared across App/Agent/CLI
public struct KeyboardLockerSettings: Equatable, Hashable, Codable, Sendable {
  /// Defines auto-unlock behavior with type-safe enum
  public enum AutoUnlockPolicy: Equatable, Hashable, Codable, Sendable, Identifiable {
    /// Never auto-unlock until user explicitly triggers unlock
    case disabled
    /// Auto-unlock after specified timeout
    case timed(seconds: TimeInterval)

    /// Identifiable conformance using self as ID
    public var id: Self { self }

    /// Converts policy to timeout in seconds, nil when disabled
    public var timeout: TimeInterval? {
      switch self {
      case .disabled:
        nil
      case let .timed(seconds):
        seconds
      }
    }

    private enum PresetTimeouts {
      static let short: TimeInterval = 30
      static let medium: TimeInterval = 60
      static let long: TimeInterval = 120
    }

    /// Common presets for UI binding
    public static let presets: [AutoUnlockPolicy] = [
      .disabled,
      .timed(seconds: PresetTimeouts.short),
      .timed(seconds: PresetTimeouts.medium),
      .timed(seconds: PresetTimeouts.long),
    ]
  }

  /// Represents unlock hotkey combination
  public struct Hotkey: Equatable, Hashable, Sendable {
    public var keyCode: CGKeyCode
    public var modifierFlags: CGEventFlags

    public init(keyCode: CGKeyCode, modifierFlags: CGEventFlags) {
      self.keyCode = keyCode
      self.modifierFlags = modifierFlags
    }

    /// Filters CapsLock and other irrelevant modifiers to ensure reliable matching
    private static let relevantModifierMask: CGEventFlags = [
      .maskCommand,
      .maskControl,
      .maskAlternate,
      .maskShift,
    ]

    /// Validates hotkey has at least one modifier key
    public var isValid: Bool {
      modifierFlags.intersection(Self.relevantModifierMask).isEmpty == false
    }

    /// Checks if event's keyCode and modifiers match this hotkey
    public func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
      guard keyCode == self.keyCode else {
        return false
      }
      let normalizedFlags = flags.intersection(Self.relevantModifierMask)
      return normalizedFlags == modifierFlags.intersection(Self.relevantModifierMask)
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(keyCode)
      hasher.combine(modifierFlags.rawValue)
    }
  }

  public var autoUnlockPolicy: AutoUnlockPolicy
  public var unlockHotkey: Hotkey
  public var showsUnlockNotification: Bool

  public init(
    autoUnlockPolicy: AutoUnlockPolicy,
    showsUnlockNotification: Bool,
    unlockHotkey: Hotkey
  ) {
    self.autoUnlockPolicy = autoUnlockPolicy
    self.showsUnlockNotification = showsUnlockNotification
    self.unlockHotkey = unlockHotkey
  }

  /// Default settings for initial launch or reset
  public static let `default` = KeyboardLockerSettings(
    autoUnlockPolicy: .timed(seconds: 60),
    showsUnlockNotification: true,
    unlockHotkey: Hotkey(
      keyCode: SharedConstants.defaultUnlockKeyCode,
      modifierFlags: [.maskControl, .maskCommand]
    )
  )
}

extension KeyboardLockerSettings.Hotkey: Codable {
  private enum CodingKeys: String, CodingKey {
    case keyCode
    case modifierFlags
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let keyCodeRaw = try container.decode(UInt16.self, forKey: .keyCode)
    keyCode = CGKeyCode(keyCodeRaw)
    let flagsRaw = try container.decode(UInt64.self, forKey: .modifierFlags)
    modifierFlags = CGEventFlags(rawValue: flagsRaw)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(UInt16(keyCode), forKey: .keyCode)
    try container.encode(modifierFlags.rawValue, forKey: .modifierFlags)
  }
}
