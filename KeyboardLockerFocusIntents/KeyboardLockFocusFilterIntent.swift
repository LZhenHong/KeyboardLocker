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
    "Locks the keyboard when this Focus turns on and unlocks when it turns off. Unlocking manually while the Focus is active does not re-lock. A lock taken over elsewhere stays locked."
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
