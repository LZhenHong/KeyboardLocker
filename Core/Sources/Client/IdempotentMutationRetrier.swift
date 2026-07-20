/// Retries a mutation only when the first reply times out and resets the transport boundary before
/// doing so. Callers use this only for operations whose complete semantic effect is idempotent.
enum IdempotentMutationRetrier {
  static func perform(
    operation: @escaping @Sendable () async throws -> Void,
    resetConnection: @escaping @Sendable () -> Void
  ) async throws {
    do {
      try await operation()
    } catch XPCClientError.timedOut {
      resetConnection()
      do {
        try await operation()
      } catch XPCClientError.timedOut {
        throw XPCClientError.operationOutcomeUnknown
      }
    }
  }
}
