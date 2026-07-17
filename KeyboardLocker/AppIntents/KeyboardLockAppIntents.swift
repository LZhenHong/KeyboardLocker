import AppIntents
import Foundation

@MainActor
struct LockKeyboardIntent: nonisolated AppIntent {
  nonisolated static let title: LocalizedStringResource = "Lock Keyboard"
  nonisolated static let description = IntentDescription(
    "Locks standard keyboard input while keeping mouse and media keys available."
  )

  private let client: any AgentLockActionServing

  nonisolated init() {
    client = LiveAgentClient()
  }

  nonisolated init(client: any AgentLockActionServing) {
    self.client = client
  }

  nonisolated func perform() async throws -> some IntentResult {
    try await client.lock()
    return .result()
  }
}

@MainActor
struct UnlockKeyboardIntent: nonisolated AppIntent {
  nonisolated static let title: LocalizedStringResource = "Unlock Keyboard"
  nonisolated static let description = IntentDescription("Unlocks standard keyboard input.")

  private let client: any AgentLockActionServing

  nonisolated init() {
    client = LiveAgentClient()
  }

  nonisolated init(client: any AgentLockActionServing) {
    self.client = client
  }

  nonisolated func perform() async throws -> some IntentResult {
    try await client.unlock()
    return .result()
  }
}

@MainActor
struct GetKeyboardLockStatusIntent: nonisolated AppIntent {
  nonisolated static let title: LocalizedStringResource = "Get Keyboard Lock Status"
  nonisolated static let description = IntentDescription(
    "Returns whether standard keyboard input is currently locked."
  )

  private let client: any AgentLockActionServing

  nonisolated init() {
    client = LiveAgentClient()
  }

  nonisolated init(client: any AgentLockActionServing) {
    self.client = client
  }

  nonisolated func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
    try await .result(value: client.status())
  }
}
