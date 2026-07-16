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
    do {
      try await withProxy { service, resume in
        service.lockKeyboard { resume($0) }
      }
    } catch XPCClientError.timedOut {
      try await confirmTimedOutMutation(expectedIsLocked: true)
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

  /// The Agent's current settings, falling back to `.default` if the Agent can't provide them.
  public func currentSettings() async throws -> KeyboardLockerSettings {
    let connection = try await negotiatedConnection(
      requiring: [.currentSettings]
    )
    let data: Data? = try await withProxyReturning(using: connection) { service, resume in
      service.currentSettings { resume($0, nil) }
    }
    return KeyboardLockerSettings.decodedFromXPC(data)
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
    connection.interruptionHandler = clear

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
  private func withProxyReturning<T>(
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
      let timeoutTask = Task { [weak self] in
        try? await Task.sleep(for: Self.responseTimeout)
        guard !Task.isCancelled else {
          return
        }
        once.run {
          self?.invalidateConnection(connection)
          continuation.resume(throwing: XPCClientError.timedOut)
        }
      }

      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        once.run {
          timeoutTask.cancel()
          continuation.resume(throwing: error)
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
