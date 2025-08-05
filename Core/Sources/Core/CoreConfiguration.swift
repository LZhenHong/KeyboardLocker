import Carbon
import Combine
import Foundation
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
    case launchAtLogin
    case enableSounds
    case hotkey
    case isFirstLaunch
    case appVersion
  }

  public enum Duration: Codable, Equatable, Hashable, Identifiable {
    case never
    case infinite
    case minutes(Int) // Duration in minutes

    // MARK: - Identifiable

    public var id: String {
      switch self {
      case .never:
        "never"
      case .infinite:
        "infinite"
      case let .minutes(minutes):
        "minutes_\(minutes)"
      }
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

    /// Whether auto-lock is enabled
    public var isEnabled: Bool {
      self != .never
    }
  }

  // MARK: - Published Properties with AppStorage

  /// Auto-lock configuration using enum instead of raw values
  @AppStorage("autoLockDuration") private var storedAutoLockMinutes: Int = 0

  @Published public var autoLockDuration: Duration = .never {
    didSet {
      storedAutoLockMinutes = autoLockDuration.minutes
    }
  }

  /// Whether to show system notifications
  @AppStorage("showNotifications") public var showNotifications: Bool = true

  /// Whether to launch app at login
  @AppStorage("launchAtLogin") public var launchAtLogin: Bool = false

  /// Hotkey configuration (using Carbon key codes)
  @Published public var hotkey: HotkeyConfiguration = .defaultHotkey() {
    didSet {
      if let data = try? JSONEncoder().encode(hotkey) {
        UserDefaults.standard.set(data, forKey: ConfigKeys.hotkey.rawValue)
      }
    }
  }

  // MARK: - Computed Properties

  /// Check if auto-lock is enabled
  public var isAutoLockEnabled: Bool {
    autoLockDuration.isEnabled
  }

  /// Auto-lock duration in seconds
  public var autoLockDurationInSeconds: TimeInterval {
    autoLockDuration.seconds
  }

  // MARK: - Non-Published Properties with AppStorage

  /// Whether this is the first app launch
  @AppStorage("isFirstLaunch") public var isFirstLaunch: Bool = true

  /// Current app version
  @AppStorage("appVersion") public var appVersion: String = "1.0.0"

  // MARK: - Initialization

  private init() {
    loadConfiguration()
  }

  // MARK: - Configuration Management

  /// Load configuration from UserDefaults
  public func loadConfiguration() {
    // Load auto-lock duration from stored minutes
    autoLockDuration = storedAutoLockMinutes == 0 ? .never : .minutes(storedAutoLockMinutes)

    // Load hotkey configuration
    if let data = UserDefaults.standard.data(forKey: ConfigKeys.hotkey.rawValue),
       let decodedHotkey = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data)
    {
      hotkey = decodedHotkey
    } else {
      hotkey = HotkeyConfiguration.defaultHotkey()
    }
  }

  /// Reset configuration to default values
  public func resetToDefaults() {
    autoLockDuration = .never
    showNotifications = true
    launchAtLogin = false
    hotkey = HotkeyConfiguration.defaultHotkey()
    isFirstLaunch = false
  }

  /// Export configuration as dictionary
  public func exportConfiguration() -> [String: Any] {
    [
      ConfigKeys.autoLockDuration.rawValue: autoLockDuration.minutes,
      ConfigKeys.showNotifications.rawValue: showNotifications,
      ConfigKeys.launchAtLogin.rawValue: launchAtLogin,
      ConfigKeys.hotkey.rawValue: (try? JSONEncoder().encode(hotkey)) ?? Data(),
      ConfigKeys.isFirstLaunch.rawValue: isFirstLaunch,
      ConfigKeys.appVersion.rawValue: appVersion,
    ]
  }

  /// Import configuration from dictionary
  public func importConfiguration(_ config: [String: Any]) {
    if let duration = config[ConfigKeys.autoLockDuration.rawValue] as? Int {
      autoLockDuration = duration == 0 ? .never : .minutes(duration)
    }

    if let notifications = config[ConfigKeys.showNotifications.rawValue] as? Bool {
      showNotifications = notifications
    }

    if let login = config[ConfigKeys.launchAtLogin.rawValue] as? Bool {
      launchAtLogin = login
    }

    if let hotkeyData = config[ConfigKeys.hotkey.rawValue] as? Data,
       let decodedHotkey = try? JSONDecoder().decode(HotkeyConfiguration.self, from: hotkeyData)
    {
      hotkey = decodedHotkey
    }

    if let firstLaunch = config[ConfigKeys.isFirstLaunch.rawValue] as? Bool {
      isFirstLaunch = firstLaunch
    }

    if let version = config[ConfigKeys.appVersion.rawValue] as? String {
      appVersion = version
    }
  }
}

// MARK: - Hotkey Configuration

/// Hotkey configuration structure
public struct HotkeyConfiguration: Codable, CustomStringConvertible {
  public let keyCode: UInt16
  public let modifierFlags: UInt32
  public let displayString: String

  public init(keyCode: UInt16, modifierFlags: UInt32, displayString: String) {
    self.keyCode = keyCode
    self.modifierFlags = modifierFlags
    self.displayString = displayString
  }

  /// Default hotkey: Command+Shift+L
  public static func defaultHotkey() -> HotkeyConfiguration {
    HotkeyConfiguration(
      keyCode: CoreConstants.defaultUnlockKeyCode,
      modifierFlags: UInt32(cmdKey | shiftKey),
      displayString: "⌘⇧L"
    )
  }

  public var description: String {
    displayString
  }
}
