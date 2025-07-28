import Carbon
import Combine
import Foundation

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

  // MARK: - Published Properties

  /// Auto-lock duration in minutes (0 = disabled)
  @Published public var autoLockDuration: Int = 0 {
    didSet {
      UserDefaults.standard.set(autoLockDuration, forKey: ConfigKeys.autoLockDuration.rawValue)
      print("📝 Auto-lock duration updated: \(autoLockDuration) minutes")
    }
  }

  /// Whether to show system notifications
  @Published public var showNotifications: Bool = true {
    didSet {
      UserDefaults.standard.set(showNotifications, forKey: ConfigKeys.showNotifications.rawValue)
      print("📝 Notifications setting updated: \(showNotifications)")
    }
  }

  /// Whether to launch app at login
  @Published public var launchAtLogin: Bool = false {
    didSet {
      UserDefaults.standard.set(launchAtLogin, forKey: ConfigKeys.launchAtLogin.rawValue)
      print("📝 Launch at login updated: \(launchAtLogin)")
    }
  }

  /// Whether to enable sound effects
  @Published public var enableSounds: Bool = true {
    didSet {
      UserDefaults.standard.set(enableSounds, forKey: ConfigKeys.enableSounds.rawValue)
      print("📝 Sound effects updated: \(enableSounds)")
    }
  }

  /// Hotkey configuration (using Carbon key codes)
  @Published public var hotkey: HotkeyConfiguration = .defaultHotkey() {
    didSet {
      if let data = try? JSONEncoder().encode(hotkey) {
        UserDefaults.standard.set(data, forKey: ConfigKeys.hotkey.rawValue)
        print("📝 Hotkey configuration updated: \(hotkey)")
      }
    }
  }

  // MARK: - Computed Properties

  /// Check if auto-lock is enabled
  public var isAutoLockEnabled: Bool {
    autoLockDuration > 0
  }

  /// Auto-lock duration in seconds
  public var autoLockDurationInSeconds: TimeInterval {
    TimeInterval(autoLockDuration * 60) // Convert minutes to seconds
  }

  // MARK: - Non-Published Properties

  /// Whether this is the first app launch
  public var isFirstLaunch: Bool {
    get {
      UserDefaults.standard.bool(forKey: ConfigKeys.isFirstLaunch.rawValue)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: ConfigKeys.isFirstLaunch.rawValue)
    }
  }

  /// Current app version
  public var appVersion: String {
    get {
      UserDefaults.standard.string(forKey: ConfigKeys.appVersion.rawValue) ?? "1.0.0"
    }
    set {
      UserDefaults.standard.set(newValue, forKey: ConfigKeys.appVersion.rawValue)
    }
  }

  // MARK: - Initialization

  private init() {
    loadConfiguration()
    print("🚀 CoreConfiguration initialized")
  }

  // MARK: - Configuration Management

  /// Load configuration from UserDefaults
  public func loadConfiguration() {
    autoLockDuration = UserDefaults.standard.integer(forKey: ConfigKeys.autoLockDuration.rawValue)
    showNotifications =
      UserDefaults.standard.object(forKey: ConfigKeys.showNotifications.rawValue) as? Bool ?? true
    launchAtLogin = UserDefaults.standard.bool(forKey: ConfigKeys.launchAtLogin.rawValue)
    enableSounds =
      UserDefaults.standard.object(forKey: ConfigKeys.enableSounds.rawValue) as? Bool ?? true

    // Load hotkey configuration
    if let data = UserDefaults.standard.data(forKey: ConfigKeys.hotkey.rawValue),
       let decodedHotkey = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data)
    {
      hotkey = decodedHotkey
    } else {
      hotkey = HotkeyConfiguration.defaultHotkey()
    }

    // Set first launch flag if not set
    if UserDefaults.standard.object(forKey: ConfigKeys.isFirstLaunch.rawValue) == nil {
      isFirstLaunch = true
    }

    print("📁 Configuration loaded from UserDefaults")
  }

  /// Reset configuration to default values
  public func resetToDefaults() {
    autoLockDuration = 0
    showNotifications = true
    launchAtLogin = false
    enableSounds = true
    hotkey = HotkeyConfiguration.defaultHotkey()
    isFirstLaunch = false

    print("🔄 Configuration reset to defaults")
  }

  /// Export configuration as dictionary
  public func exportConfiguration() -> [String: Any] {
    [
      ConfigKeys.autoLockDuration.rawValue: autoLockDuration,
      ConfigKeys.showNotifications.rawValue: showNotifications,
      ConfigKeys.launchAtLogin.rawValue: launchAtLogin,
      ConfigKeys.enableSounds.rawValue: enableSounds,
      ConfigKeys.hotkey.rawValue: try! JSONEncoder().encode(hotkey),
      ConfigKeys.isFirstLaunch.rawValue: isFirstLaunch,
      ConfigKeys.appVersion.rawValue: appVersion,
    ]
  }

  /// Import configuration from dictionary
  public func importConfiguration(_ config: [String: Any]) {
    if let duration = config[ConfigKeys.autoLockDuration.rawValue] as? Int {
      autoLockDuration = duration
    }

    if let notifications = config[ConfigKeys.showNotifications.rawValue] as? Bool {
      showNotifications = notifications
    }

    if let login = config[ConfigKeys.launchAtLogin.rawValue] as? Bool {
      launchAtLogin = login
    }

    if let sounds = config[ConfigKeys.enableSounds.rawValue] as? Bool {
      enableSounds = sounds
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

    print("📥 Configuration imported from dictionary")
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
      keyCode: 37, // 'L' key
      modifierFlags: UInt32(cmdKey | shiftKey),
      displayString: "⌘⇧L"
    )
  }

  public var description: String {
    displayString
  }
}
