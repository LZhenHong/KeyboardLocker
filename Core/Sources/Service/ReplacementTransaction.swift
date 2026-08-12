import Common
import Foundation

/// Server-side state machine for replacing the launchd-managed Agent.
///
/// The caller must serialize access. `AgentService` does this on the main queue.
struct ReplacementTransaction {
  struct Preparation: Equatable, Sendable {
    let ticket: ServiceReplacementTicket

    fileprivate let generation: UInt64
  }

  private enum Phase {
    case committed(ServiceReplacementTicket)
    case idle
    case prepared(Preparation)
  }

  private var generation: UInt64 = 0
  private var phase: Phase = .idle

  init() {}

  var isPending: Bool {
    switch phase {
    case .committed, .prepared:
      true
    case .idle:
      false
    }
  }

  var isCommitted: Bool {
    if case .committed = phase {
      return true
    }
    return false
  }

  var servicePhase: ServiceReplacementPhase {
    switch phase {
    case .committed:
      .committed
    case .idle:
      .inactive
    case .prepared:
      .prepared
    }
  }

  mutating func prepare(
    ticket: ServiceReplacementTicket
  ) throws -> Preparation {
    guard case .idle = phase else {
      throw ReplacementTransactionError.alreadyInProgress
    }

    generation &+= 1
    let preparation = Preparation(ticket: ticket, generation: generation)
    phase = .prepared(preparation)
    return preparation
  }

  /// Moves the drain into its fail-closed phase. Repeating the same commit is idempotent.
  mutating func commit(ticket: ServiceReplacementTicket) throws {
    switch phase {
    case let .prepared(preparation) where preparation.ticket == ticket:
      phase = .committed(ticket)

    case let .committed(activeTicket) where activeTicket == ticket:
      return

    case .committed, .idle, .prepared:
      throw ReplacementTransactionError.ticketInactive
    }
  }

  func status(for ticket: ServiceReplacementTicket) -> ServiceReplacementStatus {
    let statusPhase: ServiceReplacementPhase = switch phase {
    case let .committed(activeTicket) where activeTicket == ticket:
      .committed
    case let .prepared(preparation) where preparation.ticket == ticket:
      .prepared
    case .committed, .idle, .prepared:
      .inactive
    }
    return ServiceReplacementStatus(phase: statusPhase)
  }

  /// Cancels only work that has not yet been committed to Service Management.
  mutating func cancel(ticket: ServiceReplacementTicket) throws {
    switch phase {
    case let .prepared(preparation) where preparation.ticket == ticket:
      phase = .idle

    case .committed:
      throw ReplacementTransactionError.committedCannotCancel

    case .idle, .prepared:
      throw ReplacementTransactionError.ticketInactive
    }
  }

  /// Expires exactly the scheduled preparation. A stale timer cannot clear newer state.
  @discardableResult
  mutating func expire(
    preparation: Preparation
  ) -> Bool {
    guard case let .prepared(activePreparation) = phase,
          activePreparation == preparation
    else {
      return false
    }

    phase = .idle
    return true
  }
}

enum ReplacementTransactionError: Error, Equatable, LocalizedError {
  case alreadyInProgress
  case committedCannotCancel
  case ticketInactive

  var errorDescription: String? {
    switch self {
    case .alreadyInProgress:
      "Another agent replacement is already in progress."

    case .committedCannotCancel:
      "A committed agent replacement cannot be cancelled."

    case .ticketInactive:
      "The replacement ticket is no longer active."
    }
  }
}
