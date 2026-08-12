import Common
import Foundation

/// The `LockEngine` surface `AgentService` drives. Seamed so ServiceTests can substitute a
/// deterministic double; production creates one engine owned by the process-wide service.
@MainActor
protocol LockEngineServing {
  var isLocked: Bool { get }
  var statusSnapshot: LockStatusSnapshot { get }
  func lock(
    settings: KeyboardLockerSettings,
    allowsControlCUnlock: Bool
  ) throws -> LockRequestOutcome
  func setFocusFilterLockEnabled(_ enabled: Bool, settings: KeyboardLockerSettings) throws
  func unlock()
  func updateSettings(_ settings: KeyboardLockerSettings)
}

extension LockEngine: LockEngineServing {}

/// XPC service implementation. Owns the settings source of truth and drives the single
/// global `LockEngine`. All wrappers reach the lock exclusively through this object.
///
/// Lives in the `Service` library so the barrier, generation-fence, and error-mapping wiring
/// is unit-testable; the `KeyboardLockerAgent` executable only bootstraps the listener.
public final class AgentService: NSObject, KeyboardLockerServiceProtocol {
  private static let replacementPreparationDuration: TimeInterval = 30

  @MainActor private let descriptorResult: Result<ServiceDescriptor, Error>
  @MainActor private let settings: KeyboardLockerSettings
  @MainActor private let engine: any LockEngineServing
  @MainActor private var lockStatusNotifier: LockStatusNotifier?
  @MainActor private let expirationScheduler: MainActorTimerScheduler
  @MainActor private var replacement = ReplacementTransaction()
  @MainActor private var replacementPreparationCancellation: (() -> Void)?

  @MainActor
  init(
    descriptorResult: Result<ServiceDescriptor, Error>,
    settings: KeyboardLockerSettings,
    engine: any LockEngineServing,
    expirationScheduler: @escaping MainActorTimerScheduler
  ) {
    self.descriptorResult = descriptorResult
    self.settings = settings
    self.engine = engine
    self.expirationScheduler = expirationScheduler
    super.init()
    // Seed the engine so a lock uses persisted values.
    engine.updateSettings(settings)
  }

  @MainActor
  public convenience override init() {
    let engine = LockEngine(dependencies: .live)
    let notifier = LockStatusNotifier(
      notifications: LiveLockStatusNotificationService(),
      snapshot: { engine.statusSnapshot },
      unlock: { engine.unlock() }
    )
    engine.setStateChangeHandler { [weak notifier] in
      notifier?.lockStateDidChange()
    }

    self.init(
      descriptorResult: Result { try Self.makeServiceDescriptor() },
      settings: KeyboardLockerSettingsStore().load(),
      engine: engine,
      expirationScheduler: liveMainActorTimerScheduler
    )
    lockStatusNotifier = notifier
    notifier.start()
  }

  // MARK: - Bootstrap

  public func serviceDescriptor(reply: @escaping (Data?, Error?) -> Void) {
    executeOnMainActor {
      switch self.descriptorResult {
      case let .success(base):
        let descriptor = ServiceDescriptor(
          protocolVersion: base.protocolVersion,
          capabilities: base.capabilities,
          agentBundleIdentifier: base.agentBundleIdentifier,
          agentVersion: base.agentVersion,
          agentBuild: base.agentBuild,
          agentInstanceID: base.agentInstanceID,
          replacementPending: self.replacement.isPending,
          replacementPhase: self.replacement.servicePhase
        )
        do {
          let data = try descriptor.encodedForXPC()
          reply(data, nil)
        } catch {
          reply(nil, error)
        }

      case let .failure(error):
        reply(nil, error)
      }
    }
  }

  // MARK: - Locking

  public func lockKeyboard(reply: @escaping (Error?) -> Void) {
    executeOnMainActor {
      do {
        _ = try self.performLock(allowsControlCUnlock: false)
        reply(nil)
      } catch {
        reply(error)
      }
    }
  }

  public func lockKeyboardInteractively(
    reply: @escaping (Bool, Error?) -> Void
  ) {
    executeOnMainActor {
      do {
        let outcome = try self.performLock(allowsControlCUnlock: true)
        reply(outcome == .acquired, nil)
      } catch {
        reply(false, error)
      }
    }
  }

  public func beginSafetyCheck(
    reply: @escaping (Bool, Error?) -> Void
  ) {
    executeOnMainActor {
      do {
        try self.ensureAcceptingLockRequests()
        var safetySettings = self.settings
        safetySettings.autoUnlockPolicy = .timed(
          seconds: SharedConstants.safetyCheckDuration
        )
        let outcome = try self.engine.lock(
          settings: safetySettings,
          allowsControlCUnlock: false
        )
        reply(outcome == .acquired, nil)
      } catch {
        reply(false, error)
      }
    }
  }

  public func setFocusFilterLockEnabled(
    _ enabled: Bool,
    reply: @escaping (Error?) -> Void
  ) {
    executeOnMainActor {
      do {
        if enabled {
          try self.ensureAcceptingLockRequests()
        }
        try self.engine.setFocusFilterLockEnabled(
          enabled,
          settings: self.settings
        )
        reply(nil)
      } catch {
        reply(error)
      }
    }
  }

  public func unlockKeyboard(reply: @escaping (Error?) -> Void) {
    executeOnMainActor {
      self.engine.unlock()
      reply(nil)
    }
  }

  public func status(reply: @escaping (Bool, Error?) -> Void) {
    executeOnMainActor {
      reply(self.engine.isLocked, nil)
    }
  }

  public func toggleKeyboard(reply: @escaping (Bool, Error?) -> Void) {
    executeOnMainActor {
      do {
        reply(try self.performToggle(), nil)
      } catch {
        reply(false, error)
      }
    }
  }

  public func lockStatusSnapshot(reply: @escaping (Data?, Error?) -> Void) {
    executeOnMainActor {
      do {
        let data = try self.engine.statusSnapshot.encodedForXPC()
        reply(data, nil)
      } catch {
        reply(nil, error)
      }
    }
  }

  public func prepareForReplacement(
    unlockIfNeeded: Bool,
    expectedAgentInstanceID: UUID,
    reply: @escaping (Data?, Error?) -> Void
  ) {
    executeOnMainActor {
      guard case let .success(descriptor) = self.descriptorResult else {
        reply(nil, Self.replacementError(
          code: 2,
          description: "The agent could not create a replacement ticket."
        ))
        return
      }

      guard descriptor.agentInstanceID == expectedAgentInstanceID else {
        reply(nil, Self.replacementError(
          code: 8,
          description: "The running agent changed before replacement could be prepared."
        ))
        return
      }

      guard unlockIfNeeded || !self.engine.isLocked else {
        reply(nil, Self.replacementError(
          code: 3,
          description: "The keyboard must be unlocked before the agent can be replaced."
        ))
        return
      }

      let ticket = ServiceReplacementTicket(
        id: UUID(),
        agentInstanceID: descriptor.agentInstanceID
      )
      let data: Data
      do {
        data = try ticket.encodedForXPC()
      } catch {
        reply(nil, error)
        return
      }

      let preparation: ReplacementTransaction.Preparation
      do {
        preparation = try self.replacement.prepare(ticket: ticket)
      } catch {
        reply(nil, Self.replacementError(error))
        return
      }

      // Install the barrier before unlocking so no queued client can re-lock in between.
      self.scheduleExpiration(for: preparation)
      if unlockIfNeeded {
        self.engine.unlock()
      }
      reply(data, nil)
    }
  }

  public func commitReplacement(
    ticket data: Data,
    reply: @escaping (Error?) -> Void
  ) {
    let candidate: ServiceReplacementTicket
    do {
      candidate = try ServiceReplacementTicket.decodedFromXPC(data)
    } catch {
      reply(error)
      return
    }

    executeOnMainActor {
      do {
        try self.replacement.commit(ticket: candidate)
        self.replacementPreparationCancellation?()
        self.replacementPreparationCancellation = nil
        reply(nil)
      } catch {
        reply(Self.replacementError(error))
      }
    }
  }

  public func replacementStatus(
    ticket data: Data,
    reply: @escaping (Data?, Error?) -> Void
  ) {
    let candidate: ServiceReplacementTicket
    do {
      candidate = try ServiceReplacementTicket.decodedFromXPC(data)
    } catch {
      reply(nil, error)
      return
    }

    executeOnMainActor {
      do {
        let data = try self.replacement.status(for: candidate).encodedForXPC()
        reply(data, nil)
      } catch {
        reply(nil, error)
      }
    }
  }

  public func cancelReplacementPreparation(
    ticket data: Data,
    reply: @escaping (Error?) -> Void
  ) {
    let candidate: ServiceReplacementTicket
    do {
      candidate = try ServiceReplacementTicket.decodedFromXPC(data)
    } catch {
      reply(error)
      return
    }

    executeOnMainActor {
      do {
        try self.replacement.cancel(ticket: candidate)
        self.replacementPreparationCancellation?()
        self.replacementPreparationCancellation = nil
        reply(nil)
      } catch {
        reply(Self.replacementError(error))
      }
    }
  }

  // MARK: - Accessibility

  public func hasAccessibilityPermission(reply: @escaping (Bool) -> Void) {
    executeOnMainActor {
      reply(AccessibilityManager.hasPermission())
    }
  }

  public func requestAccessibilityPermission(reply: @escaping (Error?) -> Void) {
    executeOnMainActor {
      AccessibilityManager.requestPermission()
      reply(nil)
    }
  }

  // MARK: - Settings

  public func currentSettings(reply: @escaping (Data?) -> Void) {
    executeOnMainActor {
      reply(try? self.settings.encodedForXPC())
    }
  }

  public func currentSettingsWithError(reply: @escaping (Data?, Error?) -> Void) {
    executeOnMainActor {
      do {
        let data = try self.settings.encodedForXPC()
        reply(data, nil)
      } catch {
        reply(nil, error)
      }
    }
  }

  // MARK: - Helpers

  @MainActor
  private func performLock(
    allowsControlCUnlock: Bool
  ) throws -> LockRequestOutcome {
    try ensureAcceptingLockRequests()

    return try engine.lock(
      settings: settings,
      allowsControlCUnlock: allowsControlCUnlock
    )
  }

  /// The flip is atomic because the state read and the mutation run in one MainActor turn; no
  /// other client call can interleave and translate the request into the wrong direction.
  @MainActor
  private func performToggle() throws -> Bool {
    if engine.isLocked {
      // Symmetric with an explicit unlock: releases any generation, including a Focus-owned one.
      engine.unlock()
      return false
    }

    return try performLock(allowsControlCUnlock: false) == .acquired
  }

  @MainActor
  private func ensureAcceptingLockRequests() throws {
    guard !replacement.isPending else {
      throw Self.replacementError(
        code: 1,
        description: "The agent is preparing to be replaced and is not accepting new lock requests."
      )
    }
  }

  private static func makeServiceDescriptor(bundle: Bundle = .main) throws -> ServiceDescriptor {
    guard let bundleIdentifier = bundle.bundleIdentifier, !bundleIdentifier.isEmpty else {
      throw AgentDescriptorError.missingMetadata("CFBundleIdentifier")
    }
    guard let version = bundle.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String, !version.isEmpty else {
      throw AgentDescriptorError.missingMetadata("CFBundleShortVersionString")
    }
    guard let build = bundle.object(
      forInfoDictionaryKey: "CFBundleVersion"
    ) as? String, !build.isEmpty else {
      throw AgentDescriptorError.missingMetadata("CFBundleVersion")
    }

    return ServiceDescriptor(
      protocolVersion: ServiceContract.protocolVersion,
      capabilities: ServiceContract.requiredCapabilities,
      agentBundleIdentifier: bundleIdentifier,
      agentVersion: version,
      agentBuild: build,
      agentInstanceID: UUID()
    )
  }

  private static func replacementError(code: Int, description: String) -> NSError {
    NSError(
      domain: "\(SharedConstants.agentBundleIdentifier).replacement",
      code: code,
      userInfo: [NSLocalizedDescriptionKey: description]
    )
  }

  private static func replacementError(_ error: Error) -> NSError {
    let code = switch error as? ReplacementTransactionError {
    case .alreadyInProgress:
      5
    case .committedCannotCancel:
      6
    case .ticketInactive:
      4
    case nil:
      7
    }
    return replacementError(code: code, description: error.localizedDescription)
  }

  @MainActor
  private func scheduleExpiration(
    for preparation: ReplacementTransaction.Preparation
  ) {
    replacementPreparationCancellation?()

    replacementPreparationCancellation = expirationScheduler(
      Self.replacementPreparationDuration
    ) { [weak self] in
      guard let self else {
        return
      }
      if replacement.expire(preparation: preparation) {
        replacementPreparationCancellation = nil
      }
    }
  }

  private func executeOnMainActor(_ operation: @escaping @MainActor () -> Void) {
    let operation = MainActorOperation(operation)
    if Thread.isMainThread {
      MainActor.assumeIsolated {
        operation()
      }
    } else {
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          operation()
        }
      }
    }
  }
}

/// Immutable transfer object used to move an Objective-C XPC reply operation onto `MainActor`.
private final class MainActorOperation: @unchecked Sendable {
  private let body: @MainActor () -> Void

  init(_ body: @escaping @MainActor () -> Void) {
    self.body = body
  }

  @MainActor
  func callAsFunction() {
    body()
  }
}

private enum AgentDescriptorError: Error, LocalizedError {
  case missingMetadata(String)

  var errorDescription: String? {
    switch self {
    case let .missingMetadata(key):
      "The Agent bundle is missing required metadata: \(key)."
    }
  }
}
