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
  /// Whether the Agent plays a sound on lock/unlock transitions. Additive Codable field:
  /// payloads written before it existed decode as enabled.
  public var soundEffectsEnabled: Bool
  /// Whether the Agent nudges presentation surfaces when it swallows keystrokes while locked.
  /// Additive Codable field: payloads written before it existed decode as enabled.
  public var blockedInputFeedbackEnabled: Bool

  /// Optional global hotkey that locks the keyboard from anywhere while the App is running;
  /// nil disables it. Additive Codable field: payloads written before it existed decode as nil,
  /// and a nil value is omitted when encoding. Registered App-side (Carbon), deliberately not
  /// in the engine — see the architecture contract for the gesture asymmetry rule.
  public var lockHotkey: Hotkey?

  public init(
    autoUnlockPolicy: AutoUnlockPolicy,
    unlockHotkey: Hotkey,
    unlockPhrase: String? = nil,
    soundEffectsEnabled: Bool = true,
    blockedInputFeedbackEnabled: Bool = true,
    lockHotkey: Hotkey? = nil
  ) {
    self.autoUnlockPolicy = autoUnlockPolicy
    self.unlockHotkey = unlockHotkey
    self.unlockPhrase = unlockPhrase
    self.soundEffectsEnabled = soundEffectsEnabled
    self.blockedInputFeedbackEnabled = blockedInputFeedbackEnabled
    self.lockHotkey = lockHotkey
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

extension KeyboardLockerSettings {
  /// Customized so additive fields stay decodable from older payloads: a missing Bool decodes
  /// as its default instead of failing the whole settings read. Key names for the original
  /// fields are frozen at what synthesized Codable emitted — persisted settings and older
  /// Agents on the wire carry exactly these keys.
  private enum CodingKeys: String, CodingKey {
    case autoUnlockPolicy
    case unlockHotkey
    case unlockPhrase
    case soundEffectsEnabled
    case blockedInputFeedbackEnabled
    case lockHotkey
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    autoUnlockPolicy = try container.decode(AutoUnlockPolicy.self, forKey: .autoUnlockPolicy)
    unlockHotkey = try container.decode(Hotkey.self, forKey: .unlockHotkey)
    unlockPhrase = try container.decodeIfPresent(String.self, forKey: .unlockPhrase)
    soundEffectsEnabled = try container.decodeIfPresent(
      Bool.self, forKey: .soundEffectsEnabled
    ) ?? true
    blockedInputFeedbackEnabled = try container.decodeIfPresent(
      Bool.self, forKey: .blockedInputFeedbackEnabled
    ) ?? true
    lockHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .lockHotkey)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(autoUnlockPolicy, forKey: .autoUnlockPolicy)
    try container.encode(unlockHotkey, forKey: .unlockHotkey)
    try container.encodeIfPresent(unlockPhrase, forKey: .unlockPhrase)
    try container.encode(soundEffectsEnabled, forKey: .soundEffectsEnabled)
    try container.encode(blockedInputFeedbackEnabled, forKey: .blockedInputFeedbackEnabled)
    try container.encodeIfPresent(lockHotkey, forKey: .lockHotkey)
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
      "Use only lowercase letters, digits, and spaces, with at least one letter or digit."
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .hotkeyMissingModifier:
      "Without a modifier, another app or input method may consume the keystroke first."

    case .hotkeyUnmappable:
      "Choose a key on the current keyboard layout so the hotkey can be displayed."

    case .unlockPhraseInvalidLength:
      "At least 3 characters keeps a stray keystroke from unlocking."

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
    // An optional lock hotkey follows the same guardrails: without a modifier it would swallow
    // a plain keystroke somewhere the user did not intend, and an unmappable key could never
    // be displayed back.
    if let lockHotkey {
      _ = try lockHotkey.validated()
    }

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
      "The agent returned invalid settings."
    case .missingPayload:
      "The agent returned no settings."
    case .payloadTooLarge:
      "The agent returned oversized settings."
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
