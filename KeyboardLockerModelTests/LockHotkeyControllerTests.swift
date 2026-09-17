import Carbon
import Client
import Foundation
import Testing

@MainActor
@Suite(.serialized)
final class LockHotkeyControllerTests {
  private let hotkeyA = KeyboardLockerSettings.Hotkey(
    keyCode: 40,
    modifierFlags: [.maskControl, .maskCommand]
  )
  private let hotkeyB = KeyboardLockerSettings.Hotkey(
    keyCode: 41,
    modifierFlags: [.maskAlternate, .maskCommand]
  )

  @Test
  func updateRegistersOnlyOnActualChange() {
    var registered: [KeyboardLockerSettings.Hotkey] = []
    let controller = LockHotkeyController(
      register: { registered.append($0); return true },
      unregister: {}
    )

    controller.update(hotkey: hotkeyA)
    controller.update(hotkey: hotkeyA)

    #expect(registered == [hotkeyA])
  }

  @Test
  func changingTheHotkeyReregisters() {
    var registered: [KeyboardLockerSettings.Hotkey] = []
    let controller = LockHotkeyController(
      register: { registered.append($0); return true },
      unregister: {}
    )

    controller.update(hotkey: hotkeyA)
    controller.update(hotkey: hotkeyB)

    #expect(registered == [hotkeyA, hotkeyB])
  }

  @Test
  func clearingTheHotkeyUnregisters() {
    var unregisterCount = 0
    let controller = LockHotkeyController(
      register: { _ in true },
      unregister: { unregisterCount += 1 }
    )

    controller.update(hotkey: hotkeyA)
    controller.update(hotkey: nil)

    #expect(unregisterCount == 1)
  }

  @Test
  func registrationFailureAlertsOncePerEdit() {
    var failures: [KeyboardLockerSettings.Hotkey] = []
    let controller = LockHotkeyController(
      register: { _ in false },
      unregister: {},
      onRegistrationFailure: { failures.append($0) }
    )

    controller.update(hotkey: hotkeyA)
    // Same edit re-rendered from another snapshot must not alert again.
    controller.update(hotkey: hotkeyA)

    #expect(failures == [hotkeyA])
  }

  @Test
  func carbonModifierMappingCoversTheFourMappableFlags() {
    #expect(LockHotkeyController.carbonModifiers(for: .maskCommand) == UInt32(cmdKey))
    #expect(LockHotkeyController.carbonModifiers(for: .maskControl) == UInt32(controlKey))
    #expect(LockHotkeyController.carbonModifiers(for: .maskAlternate) == UInt32(optionKey))
    #expect(LockHotkeyController.carbonModifiers(for: .maskShift) == UInt32(shiftKey))
    #expect(
      LockHotkeyController.carbonModifiers(for: [.maskControl, .maskCommand])
        == UInt32(controlKey | cmdKey)
    )
  }

  @Test
  func carbonModifierMappingIgnoresCapsLockResidue() {
    #expect(LockHotkeyController.carbonModifiers(for: .maskAlphaShift) == 0)
    #expect(LockHotkeyController.carbonModifiers(for: [.maskCommand, .maskAlphaShift]) == UInt32(cmdKey))
  }
}
