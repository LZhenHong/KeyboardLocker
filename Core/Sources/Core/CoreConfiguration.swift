import Carbon
import SwiftUI

/// Core configuration management for KeyboardLocker
/// Handles persistent settings and configuration synchronization across all targets
public class CoreConfiguration: ObservableObject {
  // MARK: - Singleton

  public static let shared = CoreConfiguration()

  // MARK: - UserDefaults Keys

  private enum ConfigKeys: String, CaseIterable {
    case autoLockDuration
    case showNotifications
    case hotkey
    case appVersion
  }

  public enum Duration: Codable, Equatable, Hashable, Identifiable, RawRepresentable {
    case never
    case infinite
    case minutes(Int) // Duration in minutes

    // MARK: - RawRepresentable

    public var rawValue: String {
      switch self {
      case .never:
        "never"
      case .infinite:
        "infinite"
      case let .minutes(minutes):
        "minutes_\(minutes)"
      }
    }

    public init?(rawValue: String) {
      if rawValue == "never" {
        self = .never
      } else if rawValue == "infinite" {
        self = .infinite
      } else if rawValue.hasPrefix("minutes_"),
                let minutesString = rawValue.components(separatedBy: "_").last,
                let minutes = Int(minutesString)
      {
        self = .minutes(minutes)
      } else {
        return nil
      }
    }

    // MARK: - Identifiable

    public var id: String {
      rawValue
    }

    /// Convert to minutes
    public var minutes: Int {
      switch self {
      case .never:
        0
      case .infinite:
        .max
      case let .minutes(minutes):
        minutes
      }
    }

    /// Convert to seconds
    public var seconds: TimeInterval {
      switch self {
      case .never, .infinite:
        0
      case let .minutes(minutes):
        TimeInterval(minutes * 60)
      }
    }
  }

  // MARK: - Published Properties with AppStorage

  /// Auto-lock configuration using enum with RawRepresentable
  @AppStorage("io.lzhlovesjyq.keyboardlocker.autolockduration")
  public var autoLockDuration: Duration = .never

  /// Whether to show system notifications
  @AppStorage("io.lzhlovesjyq.keyboardlocker.shownotifications")
  public var showNotifications: Bool = true

  /// Hotkey configuration using RawRepresentable
  @AppStorage("io.lzhlovesjyq.keyboardlocker.hotkey")
  public var hotkey: HotkeyConfiguration = .defaultHotkey()

  // MARK: - Computed Properties

  /// Check if auto-lock is enabled
  public var isAutoLockEnabled: Bool {
    autoLockDuration != .never && autoLockDuration != .infinite
  }

  /// Auto-lock duration in seconds
  public var autoLockDurationInSeconds: TimeInterval {
    autoLockDuration.seconds
  }

  // MARK: - Initialization

  private init() {}

  // MARK: - Configuration Management

  /// Reset configuration to default values
  public func resetToDefaults() {
    autoLockDuration = .never
    showNotifications = true
    hotkey = HotkeyConfiguration.defaultHotkey()
  }

  /// Export configuration as dictionary
  public func export(with appVersion: String) -> [String: Any] {
    [
      ConfigKeys.autoLockDuration.rawValue: autoLockDuration.rawValue,
      ConfigKeys.showNotifications.rawValue: showNotifications,
      ConfigKeys.hotkey.rawValue: hotkey.rawValue,
      ConfigKeys.appVersion.rawValue: appVersion,
    ]
  }

  /// Import configuration from dictionary
  public func importConfiguration(_ config: [String: Any]) {
    if let rawValue = config[ConfigKeys.autoLockDuration.rawValue] as? String,
       let duration = Duration(rawValue: rawValue)
    {
      autoLockDuration = duration
    }

    if let notifications = config[ConfigKeys.showNotifications.rawValue] as? Bool {
      showNotifications = notifications
    }

    if let rawValue = config[ConfigKeys.hotkey.rawValue] as? String,
       let hotkeyConfig = HotkeyConfiguration(rawValue: rawValue)
    {
      hotkey = hotkeyConfig
    }

    if let _ = config[ConfigKeys.appVersion.rawValue] as? String {
      /// Store app version for compatibility checks
    }
  }
}

// MARK: - Hotkey Configuration

/// Hotkey configuration structure
public struct HotkeyConfiguration: Codable, CustomStringConvertible, RawRepresentable {
  public let keyCode: UInt16
  public let modifierFlags: UInt32
  public let displayString: String

  public init(keyCode: UInt16, modifierFlags: UInt32, displayString: String) {
    self.keyCode = keyCode
    self.modifierFlags = modifierFlags
    self.displayString = displayString
  }

  // MARK: - RawRepresentable

  public var rawValue: String {
    "\(keyCode):\(modifierFlags):\(displayString)"
  }

  public init?(rawValue: String) {
    let components = rawValue.components(separatedBy: ":")
    guard components.count == 3,
          let keyCode = UInt16(components[0]),
          let modifierFlags = UInt32(components[1])
    else {
      return nil
    }

    self.keyCode = keyCode
    self.modifierFlags = modifierFlags
    displayString = components[2]
  }

  /// Default hotkey: Command+Option+L
  public static func defaultHotkey() -> HotkeyConfiguration {
    HotkeyConfiguration(
      keyCode: CoreConstants.defaultUnlockKeyCode,
      modifierFlags: UInt32(cmdKey | optionKey),
      displayString: "⌘⌥L"
    )
  }

  public var description: String {
    displayString
  }
}
