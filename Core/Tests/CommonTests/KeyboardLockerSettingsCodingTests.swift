import Common
import Foundation
import Testing

@Suite(.serialized)
struct KeyboardLockerSettingsCodingTests {
  @Test
  func roundTripPreservesSettings() throws {
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 42),
      unlockHotkey: .init(
        keyCode: 12,
        modifierFlags: [.maskAlternate, .maskShift]
      )
    )

    #expect(try KeyboardLockerSettings.decodedFromXPC(settings.encodedForXPC()) == settings)
  }

  @Test
  func missingPayloadIsRejected() {
    #expect(throws: KeyboardLockerSettingsCodingError.missingPayload) {
      try KeyboardLockerSettings.decodedFromXPC(nil)
    }
  }

  @Test
  func invalidPayloadIsRejected() {
    #expect(throws: KeyboardLockerSettingsCodingError.invalidPayload) {
      try KeyboardLockerSettings.decodedFromXPC(Data("not-json".utf8))
    }
  }

  @Test
  func oversizedPayloadIsRejectedBeforeDecoding() {
    let payload = Data(
      repeating: 0,
      count: KeyboardLockerSettings.maximumEncodedSize + 1
    )

    #expect(throws: KeyboardLockerSettingsCodingError.payloadTooLarge) {
      try KeyboardLockerSettings.decodedFromXPC(payload)
    }
  }
}
