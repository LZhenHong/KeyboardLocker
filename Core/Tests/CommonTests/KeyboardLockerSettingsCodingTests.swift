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
      ),
      unlockPhrase: "unlock me"
    )

    #expect(try KeyboardLockerSettings.decodedFromXPC(settings.encodedForXPC()) == settings)
  }

  @Test
  func payloadWithoutUnlockPhraseDecodesAsDisabled() throws {
    // Payloads written before the phrase existed omit the key; the synthesized encoder drops
    // it whenever the value is nil, so this round trip is exactly the old wire shape.
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 42),
      unlockHotkey: .init(keyCode: 12, modifierFlags: [.maskCommand])
    )
    let payload = try JSONEncoder().encode(settings)
    #expect(!String(decoding: payload, as: UTF8.self).contains("unlockPhrase"))

    #expect(try KeyboardLockerSettings.decodedFromXPC(payload).unlockPhrase == nil)
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
