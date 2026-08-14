import Common
import Foundation
import Testing

@Suite(.serialized)
struct LockStatusSnapshotCodingTests {
  private let capturedAt = Date(timeIntervalSinceReferenceDate: 1000)

  @Test
  func roundTripPreservesAuthoritativeRuntimeDatesAndSettings() throws {
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

    #expect(decoded == snapshot)
  }

  @Test
  func unlockedSnapshotRoundTrip() throws {
    let snapshot = LockStatusSnapshot(
      capturedAt: capturedAt,
      isLocked: false,
      startedAt: nil,
      autoUnlockTargetDate: nil,
      settings: .default
    )

    let decoded = try LockStatusSnapshot.decodedFromXPC(snapshot.encodedForXPC())

    #expect(decoded == snapshot)
  }

  @Test
  func missingPayloadIsRejected() {
    #expect(throws: LockStatusSnapshotCodingError.missingPayload) {
      try LockStatusSnapshot.decodedFromXPC(nil)
    }
  }

  @Test
  func invalidPayloadIsRejected() {
    #expect(throws: LockStatusSnapshotCodingError.invalidPayload) {
      try LockStatusSnapshot.decodedFromXPC(Data("not-json".utf8))
    }
  }

  @Test
  func unsupportedFormatIsRejected() throws {
    let snapshot = LockStatusSnapshot(
      formatVersion: LockStatusSnapshot.currentFormatVersion + 1,
      capturedAt: capturedAt,
      isLocked: false,
      startedAt: nil,
      autoUnlockTargetDate: nil,
      settings: .default
    )
    let payload = try JSONEncoder().encode(snapshot)

    #expect(
      throws: LockStatusSnapshotCodingError.unsupportedFormat(
        LockStatusSnapshot.currentFormatVersion + 1
      )
    ) {
      try LockStatusSnapshot.decodedFromXPC(payload)
    }
  }

  @Test
  func inconsistentUnlockedRuntimeDatesAreRejected() throws {
    let snapshot = LockStatusSnapshot(
      capturedAt: capturedAt,
      isLocked: false,
      startedAt: capturedAt,
      autoUnlockTargetDate: nil,
      settings: .default
    )
    let payload = try JSONEncoder().encode(snapshot)

    #expect(throws: LockStatusSnapshotCodingError.invalidPayload) {
      try LockStatusSnapshot.decodedFromXPC(payload)
    }
  }

  @Test
  func oversizedPayloadIsRejectedBeforeDecoding() {
    let payload = Data(
      repeating: 0,
      count: LockStatusSnapshot.maximumEncodedSize + 1
    )

    #expect(throws: LockStatusSnapshotCodingError.payloadTooLarge) {
      try LockStatusSnapshot.decodedFromXPC(payload)
    }
  }
}
