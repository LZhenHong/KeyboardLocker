import CoreGraphics
import Foundation

// MARK: - Settings Model

/// Keyboard lock settings shared across App/Agent/CLI
public struct KeyboardLockerSettings: Equatable, Hashable, Codable, Sendable {
  /// Defines auto-unlock behavior with type-safe enum
  public enum AutoUnlockPolicy: Equatable, Hashable, Codable, Sendable, Identifiable {
    /// Never auto-unlock until user explicitly triggers unlock
    case disabled
    /// Auto-unlock after specified timeout
    case timed(seconds: TimeInterval)

    /// Identifiable conformance using self as ID
    public var id: Self {
      self
    }

    /// Converts policy to timeout in seconds, nil when disabled
    public var timeout: TimeInterval? {
      switch self {
      case .disabled:
        nil
      case let .timed(seconds):
        seconds
      }
    }
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

  public init(
    autoUnlockPolicy: AutoUnlockPolicy,
    unlockHotkey: Hotkey
  ) {
    self.autoUnlockPolicy = autoUnlockPolicy
    self.unlockHotkey = unlockHotkey
  }

  /// Default settings for initial launch or reset
  public static let `default` = KeyboardLockerSettings(
    autoUnlockPolicy: .timed(seconds: 60),
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

// MARK: - Hotkey Display

public extension KeyboardLockerSettings.Hotkey {
  /// Human-readable representation of the hotkey (e.g., "⌃⌘L")
  var displayString: String {
    KeyCodeConverter.stringFromKeyCode(keyCode, modifiers: modifierFlags) ?? "?"
  }
}

// MARK: - XPC Serialization

public enum KeyboardLockerSettingsCodingError: Error, Equatable, LocalizedError {
  case invalidPayload
  case missingPayload
  case payloadTooLarge

  public var errorDescription: String? {
    switch self {
    case .invalidPayload:
      "The KeyboardLocker agent returned invalid settings."
    case .missingPayload:
      "The KeyboardLocker agent returned no settings."
    case .payloadTooLarge:
      "The KeyboardLocker agent returned oversized settings."
    }
  }
}

public extension KeyboardLockerSettings {
  static let maximumEncodedSize = 16 * 1024

  /// Encodes settings for transport across the `@objc` XPC boundary as JSON.
  func encodedForXPC() throws -> Data {
    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumEncodedSize else {
      throw KeyboardLockerSettingsCodingError.payloadTooLarge
    }
    return data
  }

  /// Decodes the Agent's authoritative settings snapshot without inventing a wrapper-side
  /// fallback when the transport payload is absent or corrupt.
  static func decodedFromXPC(_ data: Data?) throws -> KeyboardLockerSettings {
    guard let data else {
      throw KeyboardLockerSettingsCodingError.missingPayload
    }
    guard data.count <= maximumEncodedSize else {
      throw KeyboardLockerSettingsCodingError.payloadTooLarge
    }
    do {
      return try JSONDecoder().decode(KeyboardLockerSettings.self, from: data)
    } catch {
      throw KeyboardLockerSettingsCodingError.invalidPayload
    }
  }
}
