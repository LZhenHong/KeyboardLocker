import AppKit
import Carbon
import Client
import Foundation

/// Registers the configured global lock hotkey with Carbon and fires a single intent — lock —
/// back into the coordinator.
///
/// App-side by design: `RegisterEventHotKey` needs no Accessibility permission and covers the
/// only environment the App can vouch for — itself running. The engine never learns about this
/// gesture; while locked, the event tap swallows the combination like any other key, and the
/// configured unlock gesture remains the way out. Registration and unregistration are injected
/// so the diffing logic stays unit-testable without the Carbon dispatcher.
@MainActor
final class LockHotkeyController {
  private let register: (KeyboardLockerSettings.Hotkey) -> Bool
  private let unregister: () -> Void
  private let onRegistrationFailure: (KeyboardLockerSettings.Hotkey) -> Void
  private var appliedHotkey: KeyboardLockerSettings.Hotkey?

  init(
    register: @escaping (KeyboardLockerSettings.Hotkey) -> Bool,
    unregister: @escaping () -> Void,
    onRegistrationFailure: @escaping (KeyboardLockerSettings.Hotkey) -> Void = { _ in }
  ) {
    self.register = register
    self.unregister = unregister
    self.onRegistrationFailure = onRegistrationFailure
  }

  convenience init(
    onFire: @escaping () -> Void,
    onRegistrationFailure: @escaping (KeyboardLockerSettings.Hotkey) -> Void
  ) {
    let registrar = CarbonLockHotkeyRegistrar(onFire: onFire)
    self.init(
      register: { registrar.register($0) },
      unregister: { registrar.unregister() },
      onRegistrationFailure: onRegistrationFailure
    )
  }

  /// Tracks the settings value. Registration work happens only on an actual change, so the
  /// per-snapshot render loop costs nothing and a registration failure alerts once per edit
  /// rather than on every snapshot.
  func update(hotkey: KeyboardLockerSettings.Hotkey?) {
    guard hotkey != appliedHotkey else {
      return
    }
    appliedHotkey = hotkey
    guard let hotkey else {
      unregister()
      return
    }
    if !register(hotkey) {
      onRegistrationFailure(hotkey)
    }
  }

  /// CGEventFlags → Carbon modifier bits. Testing only the four mappable flags is itself the
  /// normalization: CapsLock-style residue simply maps to nothing.
  static func carbonModifiers(for flags: CGEventFlags) -> UInt32 {
    var result: UInt32 = 0
    if flags.contains(.maskCommand) {
      result |= UInt32(cmdKey)
    }
    if flags.contains(.maskControl) {
      result |= UInt32(controlKey)
    }
    if flags.contains(.maskAlternate) {
      result |= UInt32(optionKey)
    }
    if flags.contains(.maskShift) {
      result |= UInt32(shiftKey)
    }
    return result
  }
}

/// Live Carbon registration behind `LockHotkeyController`'s seams.
@MainActor
private final class CarbonLockHotkeyRegistrar {
  private static let hotKeyID = EventHotKeyID(
    signature: OSType(0x4B4C_4F4B), // 'KLOK'
    id: 1
  )

  private let onFire: () -> Void
  private var hotKeyRef: EventHotKeyRef? = nil
  private var eventHandlerRef: EventHandlerRef? = nil

  init(onFire: @escaping () -> Void) {
    self.onFire = onFire
    installEventHandler()
  }

  deinit {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
  }

  func register(_ hotkey: KeyboardLockerSettings.Hotkey) -> Bool {
    unregister()
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(hotkey.keyCode),
      LockHotkeyController.carbonModifiers(for: hotkey.modifierFlags),
      Self.hotKeyID,
      GetApplicationEventTarget(),
      0,
      &ref
    )
    guard status == noErr else {
      return false
    }
    hotKeyRef = ref
    return true
  }

  func unregister() {
    guard let hotKeyRef else {
      return
    }
    UnregisterEventHotKey(hotKeyRef)
    self.hotKeyRef = nil
  }

  private func installEventHandler() {
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, _, userInfo in
        guard let userInfo else {
          return OSStatus(eventNotHandledErr)
        }
        Unmanaged<CarbonLockHotkeyRegistrar>.fromOpaque(userInfo)
          .takeUnretainedValue()
          .fire()
        return noErr
      },
      1,
      &spec,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandlerRef
    )
  }

  private func fire() {
    // The Carbon dispatcher runs the handler on the main run loop.
    MainActor.assumeIsolated {
      onFire()
    }
  }
}
