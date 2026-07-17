import Common
import Foundation
import XCTest

final class LockStatusSnapshotCodingTests: XCTestCase {
  private let capturedAt = Date(timeIntervalSinceReferenceDate: 1000)

  func testRoundTripPreservesAuthoritativeRuntimeDatesAndSettings() throws {
    let startedAt = capturedAt.addingTimeInterval(-10)
    let deadline = capturedAt.addingTimeInterval(50)
    let settings = KeyboardLockerSettings(
      autoUnlockPolicy: .timed(seconds: 60),
      unlockHotkey: .init(
        keyCode: 12,
        modifierFlags: [.maskAlternate, .maskShift]
      )
    )
    let snapshot = LockStatusSnapshot(
      capturedAt: capturedAt,
      isLocked: true,
      startedAt: startedAt,
      autoUnlockTargetDate: deadline,
      settings: settings
    )

    let decoded = try LockStatusSnapshot.decodedFromXPC(snapshot.encodedForXPC())

    XCTAssertEqual(decoded, snapshot)
    XCTAssertEqual(decoded.lockDuration(at: capturedAt), 10)
    XCTAssertEqual(decoded.remainingAutoUnlockTime(at: capturedAt), 50)
  }

  func testUnlockedSnapshotHasNoDerivedTimingValues() throws {
    let snapshot = LockStatusSnapshot(
      capturedAt: capturedAt,
      isLocked: false,
      startedAt: nil,
      autoUnlockTargetDate: nil,
      settings: .default
    )

    let decoded = try LockStatusSnapshot.decodedFromXPC(snapshot.encodedForXPC())

    XCTAssertNil(decoded.lockDuration(at: capturedAt))
    XCTAssertNil(decoded.remainingAutoUnlockTime(at: capturedAt))
  }

  func testMissingPayloadIsRejected() {
    XCTAssertThrowsError(try LockStatusSnapshot.decodedFromXPC(nil)) { error in
      XCTAssertEqual(error as? LockStatusSnapshotCodingError, .missingPayload)
    }
  }

  func testInvalidPayloadIsRejected() {
    XCTAssertThrowsError(
      try LockStatusSnapshot.decodedFromXPC(Data("not-json".utf8))
    ) { error in
      XCTAssertEqual(error as? LockStatusSnapshotCodingError, .invalidPayload)
    }
  }

  func testUnsupportedFormatIsRejected() throws {
    let snapshot = LockStatusSnapshot(
      formatVersion: LockStatusSnapshot.currentFormatVersion + 1,
      capturedAt: capturedAt,
      isLocked: false,
      startedAt: nil,
      autoUnlockTargetDate: nil,
      settings: .default
    )
    let payload = try JSONEncoder().encode(snapshot)

    XCTAssertThrowsError(try LockStatusSnapshot.decodedFromXPC(payload)) { error in
      XCTAssertEqual(
        error as? LockStatusSnapshotCodingError,
        .unsupportedFormat(LockStatusSnapshot.currentFormatVersion + 1)
      )
    }
  }

  func testInconsistentUnlockedRuntimeDatesAreRejected() throws {
    let snapshot = LockStatusSnapshot(
      capturedAt: capturedAt,
      isLocked: false,
      startedAt: capturedAt,
      autoUnlockTargetDate: nil,
      settings: .default
    )
    let payload = try JSONEncoder().encode(snapshot)

    XCTAssertThrowsError(try LockStatusSnapshot.decodedFromXPC(payload)) { error in
      XCTAssertEqual(error as? LockStatusSnapshotCodingError, .invalidPayload)
    }
  }

  func testOversizedPayloadIsRejectedBeforeDecoding() {
    let payload = Data(
      repeating: 0,
      count: LockStatusSnapshot.maximumEncodedSize + 1
    )

    XCTAssertThrowsError(try LockStatusSnapshot.decodedFromXPC(payload)) { error in
      XCTAssertEqual(error as? LockStatusSnapshotCodingError, .payloadTooLarge)
    }
  }
}
