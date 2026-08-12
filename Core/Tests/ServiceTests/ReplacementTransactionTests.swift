import Common
@testable import Service
import XCTest

final class ReplacementTransactionTests: XCTestCase {
  func testPrepareIsExclusive() throws {
    var transaction = ReplacementTransaction()
    let first = makeTicket()

    _ = try transaction.prepare(ticket: first)

    XCTAssertTrue(transaction.isPending)
    XCTAssertThrowsError(try transaction.prepare(ticket: makeTicket())) { error in
      XCTAssertEqual(error as? ReplacementTransactionError, .alreadyInProgress)
    }
  }

  func testPreparedTransactionCanBeCancelledOnlyByItsOwner() throws {
    var transaction = ReplacementTransaction()
    let owner = makeTicket()
    _ = try transaction.prepare(ticket: owner)

    XCTAssertThrowsError(try transaction.cancel(ticket: makeTicket())) { error in
      XCTAssertEqual(error as? ReplacementTransactionError, .ticketInactive)
    }

    try transaction.cancel(ticket: owner)
    XCTAssertFalse(transaction.isPending)
  }

  func testPreparationExpires() throws {
    var transaction = ReplacementTransaction()
    let preparation = try transaction.prepare(ticket: makeTicket())

    XCTAssertEqual(transaction.status(for: preparation.ticket).phase, .prepared)
    XCTAssertEqual(transaction.status(for: makeTicket()).phase, .inactive)
    XCTAssertTrue(transaction.expire(preparation: preparation))
    XCTAssertEqual(transaction.status(for: preparation.ticket).phase, .inactive)
    XCTAssertFalse(transaction.isPending)
  }

  func testStaleExpirationCannotClearNewPreparation() throws {
    var transaction = ReplacementTransaction()
    let first = try transaction.prepare(ticket: makeTicket())
    try transaction.cancel(ticket: first.ticket)
    let second = try transaction.prepare(ticket: makeTicket())

    XCTAssertFalse(transaction.expire(preparation: first))
    XCTAssertTrue(transaction.isPending)
    XCTAssertTrue(transaction.expire(preparation: second))
  }

  func testCommitIsIdempotentAndNonExpiring() throws {
    var transaction = ReplacementTransaction()
    let preparation = try transaction.prepare(ticket: makeTicket())

    try transaction.commit(ticket: preparation.ticket)
    try transaction.commit(ticket: preparation.ticket)

    XCTAssertTrue(transaction.isPending)
    XCTAssertTrue(transaction.isCommitted)
    XCTAssertEqual(
      transaction.status(for: preparation.ticket).phase,
      .committed
    )
    XCTAssertFalse(transaction.expire(preparation: preparation))
    XCTAssertThrowsError(try transaction.cancel(ticket: preparation.ticket)) { error in
      XCTAssertEqual(error as? ReplacementTransactionError, .committedCannotCancel)
    }
    XCTAssertTrue(transaction.isPending)
  }

  func testWrongTicketCannotCommit() throws {
    var transaction = ReplacementTransaction()
    _ = try transaction.prepare(ticket: makeTicket())

    XCTAssertThrowsError(try transaction.commit(ticket: makeTicket())) { error in
      XCTAssertEqual(error as? ReplacementTransactionError, .ticketInactive)
    }
    XCTAssertFalse(transaction.isCommitted)
  }

  private func makeTicket() -> ServiceReplacementTicket {
    ServiceReplacementTicket(id: UUID(), agentInstanceID: UUID())
  }
}
