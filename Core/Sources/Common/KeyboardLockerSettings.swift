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

    /// Filters CapsLock and other irrelevant modifiers to ensure reliable matching.
    /// Shared with `hasModifier` so validation and matching normalize against one mask.
    static let relevantModifierMask: CGEventFlags = [
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
  /// Optional type-to-unlock phrase; nil disables the gesture. Additive Codable field: payloads
  /// written before it existed decode as nil, and a nil value is omitted when encoding.
  public var unlockPhrase: String?

  public init(
    autoUnlockPolicy: AutoUnlockPolicy,
    unlockHotkey: Hotkey,
    unlockPhrase: String? = nil
  ) {
    self.autoUnlockPolicy = autoUnlockPolicy
    self.unlockHotkey = unlockHotkey
    self.unlockPhrase = unlockPhrase
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
  /// Human-readable representation of the hotkey (e.g., "⌃⌘L"). Falls back to a verbal
  /// phrase — grammatical inside "Press … to unlock" sentences — when the key code has no
  /// known glyph, so a raw "?" never reaches notification, widget, or CLI copy.
  var displayString: String {
    KeyCodeConverter.stringFromKeyCode(keyCode, modifiers: modifierFlags) ?? "the configured unlock hotkey"
  }
}

// MARK: - Validation

/// Why a candidate settings value cannot become the Agent's active configuration.
///
/// These are lock-out guardrails, not style preferences: each rejected case describes a
/// configuration from which a locked keyboard could not be recovered by the intended gesture.
public enum KeyboardLockerSettingsValidationError: Error, Equatable, LocalizedError {
  case autoUnlockNotFinite
  case autoUnlockOutOfRange(ClosedRange<TimeInterval>)
  case hotkeyMissingModifier
  case hotkeyUnmappable
  case unlockPhraseInvalidLength(ClosedRange<Int>)
  case unlockPhraseInvalidCharacters

  public var errorDescription: String? {
    switch self {
    case .autoUnlockNotFinite:
      "The auto-unlock timeout is not a finite number of seconds."

    case let .autoUnlockOutOfRange(range):
      """
      The auto-unlock timeout must be between \(Int(range.lowerBound)) and \
      \(Int(range.upperBound)) seconds.
      """

    case .hotkeyMissingModifier:
      "The unlock hotkey needs at least one modifier key (⌃, ⌥, ⇧, or ⌘)."

    case .hotkeyUnmappable:
      "The unlock hotkey uses a key this keyboard layout cannot display."

    case let .unlockPhraseInvalidLength(range):
      "The unlock phrase must be between \(range.lowerBound) and \(range.upperBound) characters."

    case .unlockPhraseInvalidCharacters:
      "The unlock phrase can only contain lowercase letters, digits, and spaces, with at least one letter or digit."
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .hotkeyMissingModifier:
      "A hotkey without modifiers can be consumed by the frontmost app or an input method before it reaches KeyboardLocker."

    case .hotkeyUnmappable:
      "Choose a key that appears on the current keyboard layout so the hotkey can be shown in the app, its notification, and the widget."

    case .unlockPhraseInvalidLength:
      "Three or more characters keeps a stray keystroke from becoming an unlock."

    case .autoUnlockNotFinite, .autoUnlockOutOfRange, .unlockPhraseInvalidCharacters:
      nil
    }
  }
}

public extension KeyboardLockerSettings {
  /// Bounds for a timed auto-unlock. The lower bound keeps a deliberate lock from expiring before
  /// the user has finished what they locked the keyboard for; the upper bound keeps the fail-safe
  /// within a window a user would actually wait out rather than force-restarting the machine.
  static let allowedAutoUnlockRange: ClosedRange<TimeInterval> = 5...3600

  /// Bounds for a type-to-unlock phrase. The lower bound keeps a stray keystroke from ending the
  /// lock; the upper bound keeps a gesture that must be typed blind practical.
  static let allowedUnlockPhraseLength: ClosedRange<Int> = 3...64

  /// Lowercase letters, digits, and spaces: typeable on every ASCII-capable layout, and exactly
  /// the set the engine's phrase matcher ingests. Uppercase input is lowercased before testing.
  static func isAllowedInUnlockPhrase(_ character: Character) -> Bool {
    character == " " || (character.isASCII && (character.isLetter || character.isNumber))
  }

  /// Normalizes and validates a candidate phrase: lowercased, bounded length, restricted
  /// character set, and at least one letter or digit so a held spacebar cannot be the gesture.
  static func normalizedUnlockPhrase(_ phrase: String) throws -> String {
    let lowered = phrase.lowercased()
    guard Self.allowedUnlockPhraseLength.contains(lowered.count) else {
      throw KeyboardLockerSettingsValidationError.unlockPhraseInvalidLength(
        Self.allowedUnlockPhraseLength
      )
    }
    guard lowered.allSatisfy(Self.isAllowedInUnlockPhrase),
          lowered.contains(where: { $0 != " " })
    else {
      throw KeyboardLockerSettingsValidationError.unlockPhraseInvalidCharacters
    }
    return lowered
  }

  /// Returns the normalized settings the Agent may store, or throws when a value would leave a
  /// locked keyboard unrecoverable by its configured gesture.
  ///
  /// Lives in `Common` because the Agent owns enforcement while wrappers need the same rules for
  /// immediate feedback — duplicating them in a wrapper would let the two drift apart.
  func validated() throws -> Self {
    _ = try unlockHotkey.validated()

    var normalized = self
    if let unlockPhrase {
      normalized.unlockPhrase = try Self.normalizedUnlockPhrase(unlockPhrase)
    }
    if case let .timed(seconds) = autoUnlockPolicy {
      guard seconds.isFinite else {
        throw KeyboardLockerSettingsValidationError.autoUnlockNotFinite
      }
      // Round before the range check so a value that only differs sub-second from a bound is
      // accepted rather than rejected for a difference the UI cannot even express.
      let wholeSeconds = seconds.rounded()
      guard Self.allowedAutoUnlockRange.contains(wholeSeconds) else {
        throw KeyboardLockerSettingsValidationError.autoUnlockOutOfRange(
          Self.allowedAutoUnlockRange
        )
      }
      normalized.autoUnlockPolicy = .timed(seconds: wholeSeconds)
    }
    return normalized
  }
}

public extension KeyboardLockerSettings.Hotkey {
  /// Whether the hotkey carries at least one modifier that survives event-tap normalization.
  ///
  /// Deliberately measured against the same mask `matches(keyCode:flags:)` normalizes with, so
  /// validation can never accept a modifier the matcher would then discard.
  var hasModifier: Bool {
    !modifierFlags.intersection(Self.relevantModifierMask).isEmpty
  }

  /// Returns the hotkey when it can actually unlock a locked keyboard, or throws explaining why
  /// it cannot. Split out from `KeyboardLockerSettings.validated()` so a hotkey picker can give
  /// per-keystroke feedback against the same rule the Agent enforces.
  func validated() throws -> Self {
    guard hasModifier else {
      throw KeyboardLockerSettingsValidationError.hotkeyMissingModifier
    }
    guard KeyCodeConverter.stringFromKeyCode(keyCode, modifiers: modifierFlags) != nil else {
      throw KeyboardLockerSettingsValidationError.hotkeyUnmappable
    }
    return self
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
