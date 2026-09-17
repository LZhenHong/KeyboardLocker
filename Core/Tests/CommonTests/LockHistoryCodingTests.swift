import Common
import Foundation
import Testing

@Suite(.serialized)
struct LockHistoryCodingTests {
  private let referenceDate = Date(timeIntervalSinceReferenceDate: 10_000)

  @Test
  func roundTripPreservesEntries() throws {
    let history = LockHistory(entries: [
      LockHistoryEntry(
        startedAt: referenceDate,
        endedAt: referenceDate.addingTimeInterval(90),
        reason: .gesture
      ),
      LockHistoryEntry(
        startedAt: referenceDate.addingTimeInterval(200),
        endedAt: referenceDate.addingTimeInterval(260),
        reason: .autoUnlock
      ),
    ])

    #expect(try LockHistory.decodedFromXPC(history.encodedForXPC()) == history)
  }

  @Test
  func emptyHistoryRoundTrips() throws {
    let history = LockHistory(entries: [])
    #expect(try LockHistory.decodedFromXPC(history.encodedForXPC()) == history)
  }

  @Test
  func unknownFutureReasonDecodesLosslessly() throws {
    // `UnlockRecord.Reason` is RawRepresentable on purpose: a reason introduced by a newer
    // Agent must survive the trip through an older client.
    let history = LockHistory(entries: [
      LockHistoryEntry(
        startedAt: referenceDate,
        endedAt: referenceDate.addingTimeInterval(10),
        reason: .init(rawValue: "someFutureReason")
      ),
    ])

    let decoded = try LockHistory.decodedFromXPC(history.encodedForXPC())
    #expect(decoded.entries.first?.reason.rawValue == "someFutureReason")
  }

  @Test
  func missingPayloadIsRejected() {
    #expect(throws: LockHistoryCodingError.missingPayload) {
      try LockHistory.decodedFromXPC(nil)
    }
  }

  @Test
  func invalidPayloadIsRejected() {
    #expect(throws: LockHistoryCodingError.invalidPayload) {
      try LockHistory.decodedFromXPC(Data("not-json".utf8))
    }
  }

  @Test
  func oversizedPayloadIsRejectedBeforeDecoding() {
    let payload = Data(repeating: 0, count: LockHistory.maximumEncodedSize + 1)

    #expect(throws: LockHistoryCodingError.payloadTooLarge) {
      try LockHistory.decodedFromXPC(payload)
    }
  }

  @Test
  func unsupportedFormatVersionIsRejected() throws {
    let payload = try JSONEncoder().encode(LockHistory(formatVersion: 99, entries: []))

    #expect(throws: LockHistoryCodingError.unsupportedFormat(99)) {
      try LockHistory.decodedFromXPC(payload)
    }
  }
}
