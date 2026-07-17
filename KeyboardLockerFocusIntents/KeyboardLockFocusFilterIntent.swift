import AppIntents
import Client

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
    "Locks keyboard input while this Focus is active."
  )

  @Parameter(title: "Lock Keyboard", default: false)
  var lockKeyboard: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: lockKeyboard ? "Lock Keyboard" : "Do Not Lock Keyboard"
    )
  }

  private let client: any AgentFocusLockServing

  init() {
    client = LiveAgentFocusLockClient()
    lockKeyboard = false
  }

  init(
    lockKeyboard: Bool,
    client: any AgentFocusLockServing = LiveAgentFocusLockClient()
  ) {
    self.client = client
    self.lockKeyboard = lockKeyboard
  }

  static func suggestedFocusFilters(
    for _: FocusFilterSuggestionContext
  ) async -> [Self] {
    [Self(lockKeyboard: true)]
  }

  func perform() async throws -> some IntentResult {
    try await client.setFocusFilterLockEnabled(lockKeyboard)
    return .result()
  }
}
