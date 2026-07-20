import Common
import Foundation
import os

public enum XPCClientError: Error, LocalizedError {
  case agentChanged(expected: UUID, actual: UUID)
  case missingCapability(ServiceCapability)
  case operationOutcomeUnknown
  case peerAuthenticationUnavailable(String)
  case serviceUnavailable
  case timedOut

  public var errorDescription: String? {
    switch self {
    case let .agentChanged(expected, actual):
      """
      The KeyboardLocker agent changed after negotiation \
      (expected \(expected.uuidString), found \(actual.uuidString)).
      """

    case let .missingCapability(capability):
      "The KeyboardLocker agent does not support \(capability.rawValue)."

    case .operationOutcomeUnknown:
      "The KeyboardLocker agent did not confirm the operation. Its final outcome is unknown."

    case let .peerAuthenticationUnavailable(message):
      "XPC peer authentication could not be configured. \(message)"

    case .serviceUnavailable:
      "The KeyboardLocker agent is not reachable."

    case .timedOut:
      "The KeyboardLocker agent did not respond in time."
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .missingCapability:
      "Open KeyboardLocker to update its background agent, then retry."

    case .operationOutcomeUnknown:
      "Inspect the current state, then repeat the intended lock or unlock action if needed."

    case .serviceUnavailable:
      "Open KeyboardLocker once to register its background agent, then retry. If KeyboardLocker is already running, choose Show Details… from its menu."

    default:
      nil
    }
  }
}

/// Async client for the KeyboardLocker Agent.
///
/// Every operation is a **stateless one-off call** to the single global lock owned by the Agent —
/// there is no client-owned "session". State is observed via `LockStateSubscriber`, never inferred
/// from whether a call succeeded.
///
/// A single connection is reused and lazily recreated after invalidation, so callers survive the
/// Agent being relaunched on demand by `launchd`.
public final class XPCClient: @unchecked Sendable {
  public static let shared = XPCClient()

  private static let agentCodeSigningRequirement = Result {
    try XPCCodeSigningRequirement.sameTeam(
      identifiers: [SharedConstants.agentBundleIdentifier]
    )
  }

  private static let responseTimeout: Duration = .seconds(5)

  private let lock = OSAllocatedUnfairLock()
  private var connection: NSXPCConnection?

  private init() {}

  // MARK: - Operations

  /// Version and capabilities of the Agent process behind the current connection.
  ///
  /// Capability-gated methods repeat this negotiation on the exact connection they invoke.
  public func serviceDescriptor() async throws -> ServiceDescriptor {
    try await serviceDescriptor(using: currentConnection())
  }

  private func serviceDescriptor(
    using connection: NSXPCConnection
  ) async throws -> ServiceDescriptor {
    let data: Data? = try await withProxyReturning(using: connection) { service, resume in
      service.serviceDescriptor { resume($0, $1) }
    }
    return try ServiceDescriptor.decodedFromXPC(data)
  }

  public func lock() async throws {
    // A general desired-lock can take persistence over from a Focus-created lock even when the
    // physical state is already locked. Status cannot prove that this semantic mutation ran,
    // so retry the idempotent request and require a reply from a fresh connection.
    try await IdempotentMutationRetrier.perform(
      operation: { [self] in
        try await lockOnce()
      },
      resetConnection: { [self] in
        resetConnection()
      }
    )
  }

  private func lockOnce() async throws {
    try await withProxy { service, resume in
      service.lockKeyboard { resume($0) }
    }
  }

  /// Atomically creates an interactive global lock or reports that one was already active.
  ///
  /// A newly acquired lock treats Control-C as an additional Agent-side unlock gesture. This
  /// outcome does not grant client ownership; it only describes whether this request performed
  /// the unlocked-to-locked transition.
  public func lockInteractively() async throws -> LockRequestOutcome {
    let connection = try await negotiatedConnection(
      requiring: [.interactiveLock]
    )

    do {
      let didAcquireLock: Bool = try await withProxyReturning(
        using: connection
      ) { service, resume in
        service.lockKeyboardInteractively { resume($0, $1) }
      }
      return didAcquireLock ? .acquired : .alreadyLocked
    } catch XPCClientError.timedOut {
      // Status alone cannot recover whether this request created a lock or observed an existing
      // one, so a lost mutation reply must remain explicitly unknown.
      throw XPCClientError.operationOutcomeUnknown
    }
  }

  /// Applies the system Focus Filter state through an ownership-aware Agent operation.
  public func setFocusFilterLockEnabled(_ enabled: Bool) async throws {
    // Both enable and disable are idempotent, but status alone cannot reveal whether Focus owns
    // the current generation. Re-negotiate and require one confirmed reply.
    try await IdempotentMutationRetrier.perform(
      operation: { [self] in
        try await setFocusFilterLockEnabledOnce(enabled)
      },
      resetConnection: { [self] in
        resetConnection()
      }
    )
  }

  private func setFocusFilterLockEnabledOnce(_ enabled: Bool) async throws {
    let connection = try await negotiatedConnection(
      requiring: [.focusFilterLock]
    )
    try await withProxy(using: connection) { service, resume in
      service.setFocusFilterLockEnabled(enabled, reply: resume)
    }
  }

  public func unlock() async throws {
    do {
      try await withProxy { service, resume in
        service.unlockKeyboard { resume($0) }
      }
    } catch XPCClientError.timedOut {
      try await confirmTimedOutMutation(expectedIsLocked: false)
    }
  }

  /// Current global lock state.
  public func status() async throws -> Bool {
    try await withProxyReturning { service, resume in
      service.status { isLocked, error in resume(isLocked, error) }
    }
  }

  /// One authoritative point-in-time snapshot of the global lock and its active settings.
  public func lockStatusSnapshot() async throws -> LockStatusSnapshot {
    let connection = try await negotiatedConnection(
      requiring: [.lockStatusSnapshot]
    )
    let data: Data? = try await withProxyReturning(using: connection) { service, resume in
      service.lockStatusSnapshot { resume($0, $1) }
    }
    return try LockStatusSnapshot.decodedFromXPC(data)
  }

  /// Enters the Agent's fail-safe replacement drain and returns its ownership ticket.
  public func prepareForReplacement(
    unlockIfNeeded: Bool,
    expectedAgentInstanceID: UUID
  ) async throws -> ServiceReplacementTicket {
    let connection = try await negotiatedConnection(
      requiring: [.committedReplacementDrain, .prepareForReplacement],
      expectedAgentInstanceID: expectedAgentInstanceID
    )
    let data: Data? = try await withProxyReturning(using: connection) { service, resume in
      service.prepareForReplacement(
        unlockIfNeeded: unlockIfNeeded,
        expectedAgentInstanceID: expectedAgentInstanceID
      ) {
        resume($0, $1)
      }
    }
    let ticket = try ServiceReplacementTicket.decodedFromXPC(data)
    guard ticket.agentInstanceID == expectedAgentInstanceID else {
      try? await cancelReplacementPreparation(ticket: ticket)
      throw XPCClientError.agentChanged(
        expected: expectedAgentInstanceID,
        actual: ticket.agentInstanceID
      )
    }
    return ticket
  }

  /// Releases a replacement preparation before it has been committed.
  public func cancelReplacementPreparation(
    ticket: ServiceReplacementTicket
  ) async throws {
    let connection = try await negotiatedConnection(
      requiring: [.prepareForReplacement],
      expectedAgentInstanceID: ticket.agentInstanceID
    )
    let data = try ticket.encodedForXPC()
    try await withProxy(using: connection) { service, resume in
      service.cancelReplacementPreparation(ticket: data, reply: resume)
    }
  }

  /// Makes a prepared drain non-expiring immediately before unregister is submitted.
  public func commitReplacement(
    ticket: ServiceReplacementTicket
  ) async throws {
    do {
      try await commitReplacementOnce(ticket: ticket)
    } catch {
      // Commit is idempotent. Re-negotiate once so a lost reply cannot strand a preparation
      // merely because the original connection was interrupted.
      resetConnection()
      do {
        try await commitReplacementOnce(ticket: ticket)
      } catch let retryError {
        if let status = try? await replacementStatus(ticket: ticket),
           status.phase == .committed
        {
          return
        }
        throw retryError
      }
    }
  }

  private func commitReplacementOnce(
    ticket: ServiceReplacementTicket
  ) async throws {
    let connection = try await negotiatedConnection(
      requiring: [.committedReplacementDrain],
      expectedAgentInstanceID: ticket.agentInstanceID
    )
    let data = try ticket.encodedForXPC()
    try await withProxy(using: connection) { service, resume in
      service.commitReplacement(ticket: data, reply: resume)
    }
  }

  public func replacementStatus(
    ticket: ServiceReplacementTicket
  ) async throws -> ServiceReplacementStatus {
    let connection = try await negotiatedConnection(
      requiring: [.committedReplacementDrain],
      expectedAgentInstanceID: ticket.agentInstanceID
    )
    let ticketData = try ticket.encodedForXPC()
    let statusData: Data? = try await withProxyReturning(using: connection) { service, resume in
      service.replacementStatus(ticket: ticketData) {
        resume($0, $1)
      }
    }
    return try ServiceReplacementStatus.decodedFromXPC(statusData)
  }

  /// Whether the Agent process currently has Accessibility permission.
  public func hasAccessibilityPermission() async throws -> Bool {
    let connection = try await negotiatedConnection(
      requiring: [.accessibilityStatus]
    )
    return try await withProxyReturning(using: connection) { service, resume in
      service.hasAccessibilityPermission { resume($0, nil) }
    }
  }

  /// Requests the system Accessibility prompt from the Agent process.
  /// Completion means the request was sent; permission must be queried again later.
  public func requestAccessibilityPermission() async throws {
    let connection = try await negotiatedConnection(
      requiring: [.accessibilityPrompt]
    )
    do {
      try await withProxy(using: connection) { service, resume in
        service.requestAccessibilityPermission(reply: resume)
      }
    } catch XPCClientError.timedOut {
      throw XPCClientError.operationOutcomeUnknown
    }
  }

  /// The Agent's authoritative current settings.
  public func currentSettings() async throws -> KeyboardLockerSettings {
    let connection = try await negotiatedConnection(
      requiring: [.currentSettingsWithError]
    )
    let data: Data? = try await withProxyReturning(using: connection) { service, resume in
      service.currentSettingsWithError { resume($0, $1) }
    }
    return try KeyboardLockerSettings.decodedFromXPC(data)
  }

  // MARK: - Connection Management

  /// Invalidates the cached connection so a subsequent call resolves the currently registered
  /// Agent instead of reusing a connection to a process being replaced.
  public func resetConnection() {
    lock.lock()
    let candidate = connection
    connection = nil
    lock.unlock()
    candidate?.invalidate()
  }

  /// Lock mutations are idempotent, so a timed-out reply can be recovered by checking whether
  /// the Agent reached the requested global state through a fresh connection.
  private func confirmTimedOutMutation(expectedIsLocked: Bool) async throws {
    if let isLocked = try? await status(), isLocked == expectedIsLocked {
      return
    }
    throw XPCClientError.operationOutcomeUnknown
  }

  /// Returns one negotiated connection generation. The subsequent feature call must use this
  /// exact object; transparent reconnection would invalidate the descriptor and capability grant.
  private func negotiatedConnection(
    requiring capabilities: Set<ServiceCapability>,
    expectedAgentInstanceID: UUID? = nil
  ) async throws -> NSXPCConnection {
    let connection = try currentConnection()
    let descriptor = try await serviceDescriptor(using: connection)

    if let expectedAgentInstanceID,
       descriptor.agentInstanceID != expectedAgentInstanceID
    {
      throw XPCClientError.agentChanged(
        expected: expectedAgentInstanceID,
        actual: descriptor.agentInstanceID
      )
    }
    if let missingCapability = capabilities
      .subtracting(descriptor.capabilities)
      .sorted(by: { $0.rawValue < $1.rawValue })
      .first
    {
      throw XPCClientError.missingCapability(missingCapability)
    }
    return connection
  }

  private func currentConnection() throws -> NSXPCConnection {
    let codeSigningRequirement: String
    do {
      codeSigningRequirement = try Self.agentCodeSigningRequirement.get()
    } catch {
      throw XPCClientError.peerAuthenticationUnavailable(error.localizedDescription)
    }

    lock.lock()
    defer { lock.unlock() }

    if let connection {
      return connection
    }

    let connection = NSXPCConnection(machServiceName: SharedConstants.machServiceName)
    connection.remoteObjectInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
    connection.setCodeSigningRequirement(codeSigningRequirement)

    // Drop the cached connection on teardown so the next call transparently reconnects.
    let connectionID = ObjectIdentifier(connection)
    let clear: @Sendable () -> Void = { [weak self] in
      self?.clearConnection(ifMatching: connectionID)
    }
    connection.invalidationHandler = clear
    connection.interruptionHandler = { [weak self, weak connection] in
      guard let connection else {
        return
      }

      // An interrupted named connection may transparently attach to a different Agent process.
      // Invalidate this object so a descriptor/capability grant can never cross process
      // generations; the next operation must create a fresh connection and negotiate again.
      self?.invalidateConnection(connection)
    }

    connection.activate()
    self.connection = connection
    return connection
  }

  private func clearConnection(ifMatching candidateID: ObjectIdentifier) {
    lock.lock()
    if let activeConnection = connection, ObjectIdentifier(activeConnection) == candidateID {
      connection = nil
    }
    lock.unlock()
  }

  private func invalidateConnection(_ candidate: NSXPCConnection) {
    clearConnection(ifMatching: ObjectIdentifier(candidate))
    candidate.invalidate()
  }

  /// Bridges a reply-based XPC call returning only an optional `Error` into async/throwing form.
  /// The continuation is resumed exactly once — whether by the reply, the proxy error handler,
  /// or a missing proxy — so a dead Agent throws rather than hanging forever.
  private func withProxy(
    using connection: NSXPCConnection? = nil,
    _ body: @escaping (KeyboardLockerServiceProtocol, _ resume: @escaping (Error?) -> Void) -> Void
  ) async throws {
    let _: Void = try await withProxyReturning(using: connection) { service, resume in
      body(service) { error in
        resume((), error)
      }
    }
  }

  /// Central reply bridge. Every operation has a bounded response time and resumes exactly once
  /// across reply, proxy-error, missing-proxy, and timeout races.
  private func withProxyReturning<T: Sendable>(
    using providedConnection: NSXPCConnection? = nil,
    _ body: @escaping (KeyboardLockerServiceProtocol, _ resume: @escaping (T, Error?) -> Void) -> Void
  ) async throws -> T {
    let connection = if let providedConnection {
      providedConnection
    } else {
      try currentConnection()
    }

    return try await withCheckedThrowingContinuation { continuation in
      let once = ResumeOnce()
      let connectionReference = XPCConnectionReference(connection)
      let timeoutTask = Task { [weak self] in
        try? await Task.sleep(for: Self.responseTimeout)
        guard !Task.isCancelled else {
          return
        }
        once.run {
          self?.invalidateConnection(connectionReference.value)
          continuation.resume(throwing: XPCClientError.timedOut)
        }
      }

      let proxy = connectionReference.value.remoteObjectProxyWithErrorHandler { error in
        once.run {
          timeoutTask.cancel()
          continuation.resume(throwing: Self.normalizedProxyError(error))
        }
      }

      guard let service = proxy as? KeyboardLockerServiceProtocol else {
        once.run {
          timeoutTask.cancel()
          continuation.resume(throwing: XPCClientError.serviceUnavailable)
        }
        return
      }

      body(service) { value, error in
        once.run {
          timeoutTask.cancel()
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: value)
          }
        }
      }
    }
  }

  /// A proxy error means the request did not reach a callable XPC peer. Keep Foundation's
  /// transport details behind the Client boundary so every wrapper can present one actionable
  /// service-availability failure.
  static func normalizedProxyError(_: Error) -> Error {
    return XPCClientError.serviceUnavailable
  }
}

/// Foundation documents `NSXPCConnection` as supporting calls from multiple threads. This box
/// makes that external synchronization contract explicit when a connection is shared with the
/// timeout task that can invalidate it.
private final class XPCConnectionReference: @unchecked Sendable {
  let value: NSXPCConnection

  init(_ value: NSXPCConnection) {
    self.value = value
  }
}

/// Guarantees a continuation is resumed at most once across the reply and error-handler races.
private final class ResumeOnce: @unchecked Sendable {
  private let lock = OSAllocatedUnfairLock()
  private var done = false

  func run(_ block: () -> Void) {
    lock.lock()
    let shouldRun = !done
    done = true
    lock.unlock()
    if shouldRun {
      block()
    }
  }
}
