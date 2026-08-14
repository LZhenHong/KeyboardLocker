import AppIntents
import Client
import SystemSurfaces

protocol AgentFocusLockServing: Sendable {
  func setFocusFilterLockEnabled(_ enabled: Bool) async throws
}

struct LiveAgentFocusLockClient: AgentFocusLockServing {
  func setFocusFilterLockEnabled(_ enabled: Bool) async throws {
    try await XPCClient.shared.setFocusFilterLockEnabled(enabled)
  }
}

struct KeyboardLockFocusFilterIntent: SetFocusFilterIntent {
  static let title: LocalizedStringResource = "Keyboard Lock"
  static let description = IntentDescription(
    "Creates a keyboard lock when this Focus activates and releases it when the Focus turns off. If you unlock it while the Focus is active, it won't automatically re-lock. A lock taken over by another action stays locked."
  )

  @Parameter(title: "Lock Keyboard", default: false)
  var lockKeyboard: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: lockKeyboard ? "Lock Keyboard" : "Do Not Lock Keyboard"
    )
  }

  private let client: any AgentFocusLockServing
  private let surfaceInvalidator: LockStateSurfaceInvalidator

  init() {
    client = LiveAgentFocusLockClient()
    surfaceInvalidator = .live
    lockKeyboard = false
  }

  init(
    lockKeyboard: Bool,
    client: any AgentFocusLockServing = LiveAgentFocusLockClient(),
    surfaceInvalidator: LockStateSurfaceInvalidator = .live
  ) {
    self.client = client
    self.surfaceInvalidator = surfaceInvalidator
    self.lockKeyboard = lockKeyboard
  }

  static func suggestedFocusFilters(
    for _: FocusFilterSuggestionContext
  ) async -> [Self] {
    [Self(lockKeyboard: true)]
  }

  func perform() async throws -> some IntentResult {
    try await client.setFocusFilterLockEnabled(lockKeyboard)
    surfaceInvalidator.invalidate()
    return .result()
  }
}
