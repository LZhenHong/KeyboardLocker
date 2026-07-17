import Common
import Foundation
import XCTest

final class KeyboardLockerSettingsCodingTests: XCTestCase {
  func testRoundTripPreservesSettings() throws {
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 42),
      unlockHotkey: .init(
        keyCode: 12,
        modifierFlags: [.maskAlternate, .maskShift]
      )
    )

    XCTAssertEqual(
      try KeyboardLockerSettings.decodedFromXPC(settings.encodedForXPC()),
      settings
    )
  }

  func testMissingPayloadIsRejected() {
    XCTAssertThrowsError(try KeyboardLockerSettings.decodedFromXPC(nil)) { error in
      XCTAssertEqual(
        error as? KeyboardLockerSettingsCodingError,
        .missingPayload
      )
    }
  }

  func testInvalidPayloadIsRejected() {
    XCTAssertThrowsError(
      try KeyboardLockerSettings.decodedFromXPC(Data("not-json".utf8))
    ) { error in
      XCTAssertEqual(
        error as? KeyboardLockerSettingsCodingError,
        .invalidPayload
      )
    }
  }

  func testOversizedPayloadIsRejectedBeforeDecoding() {
    let payload = Data(
      repeating: 0,
      count: KeyboardLockerSettings.maximumEncodedSize + 1
    )

    XCTAssertThrowsError(try KeyboardLockerSettings.decodedFromXPC(payload)) { error in
      XCTAssertEqual(
        error as? KeyboardLockerSettingsCodingError,
        .payloadTooLarge
      )
    }
  }
}
