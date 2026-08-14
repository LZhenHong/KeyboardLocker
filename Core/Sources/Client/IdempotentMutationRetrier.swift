/// Retries a mutation only when its reply is lost — timed out, or dropped with a dying peer —
/// and resets the transport boundary before doing so. Callers use this only for operations
/// whose complete semantic effect is idempotent.
enum IdempotentMutationRetrier {
  static func perform(
    operation: @escaping @Sendable () async throws -> Void,
    resetConnection: @escaping @Sendable () -> Void
  ) async throws {
    do {
      try await operation()
    } catch XPCClientError.timedOut, is LostReplyError {
      resetConnection()
      do {
        try await operation()
      } catch XPCClientError.timedOut, is LostReplyError {
        throw XPCClientError.operationOutcomeUnknown
      }
    }
  }
}
