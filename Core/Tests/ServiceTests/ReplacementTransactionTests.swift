import Common
import Foundation
@testable import Service
import Testing

@Suite(.serialized)
struct ReplacementTransactionTests {
  @Test
  func prepareIsExclusive() throws {
    var transaction = ReplacementTransaction()
    let first = makeTicket()

    _ = try transaction.prepare(ticket: first)

    #expect(transaction.isPending)
    #expect(throws: ReplacementTransactionError.alreadyInProgress) {
      try transaction.prepare(ticket: makeTicket())
    }
  }

  @Test
  func preparedTransactionCanBeCancelledOnlyByItsOwner() throws {
    var transaction = ReplacementTransaction()
    let owner = makeTicket()
    _ = try transaction.prepare(ticket: owner)

    #expect(throws: ReplacementTransactionError.ticketInactive) {
      try transaction.cancel(ticket: makeTicket())
    }

    try transaction.cancel(ticket: owner)
    #expect(!transaction.isPending)
  }

  @Test
  func preparationExpires() throws {
    var transaction = ReplacementTransaction()
    let preparation = try transaction.prepare(ticket: makeTicket())

    #expect(transaction.status(for: preparation.ticket).phase == .prepared)
    #expect(transaction.status(for: makeTicket()).phase == .inactive)
    let didExpire = transaction.expire(preparation: preparation)
    #expect(didExpire)
    #expect(transaction.status(for: preparation.ticket).phase == .inactive)
    #expect(!transaction.isPending)
  }

  @Test
  func staleExpirationCannotClearNewPreparation() throws {
    var transaction = ReplacementTransaction()
    let first = try transaction.prepare(ticket: makeTicket())
    try transaction.cancel(ticket: first.ticket)
    let second = try transaction.prepare(ticket: makeTicket())

    let didExpireFirst = transaction.expire(preparation: first)
    #expect(!didExpireFirst)
    #expect(transaction.isPending)
    let didExpireSecond = transaction.expire(preparation: second)
    #expect(didExpireSecond)
  }

  @Test
  func commitIsIdempotentAndNonExpiring() throws {
    var transaction = ReplacementTransaction()
    let preparation = try transaction.prepare(ticket: makeTicket())

    try transaction.commit(ticket: preparation.ticket)
    try transaction.commit(ticket: preparation.ticket)

    #expect(transaction.isPending)
    #expect(transaction.isCommitted)
    #expect(
      transaction.status(for: preparation.ticket).phase == .committed
    )
    let didExpire = transaction.expire(preparation: preparation)
    #expect(!didExpire)
    #expect(throws: ReplacementTransactionError.committedCannotCancel) {
      try transaction.cancel(ticket: preparation.ticket)
    }
    #expect(transaction.isPending)
  }

  @Test
  func wrongTicketCannotCommit() throws {
    var transaction = ReplacementTransaction()
    _ = try transaction.prepare(ticket: makeTicket())

    #expect(throws: ReplacementTransactionError.ticketInactive) {
      try transaction.commit(ticket: makeTicket())
    }
    #expect(!transaction.isCommitted)
  }

  private func makeTicket() -> ServiceReplacementTicket {
    ServiceReplacementTicket(id: UUID(), agentInstanceID: UUID())
  }
}
