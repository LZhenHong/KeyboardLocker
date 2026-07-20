import AppIntents
import Foundation

@MainActor
struct LockKeyboardIntent: nonisolated AppIntent {
  nonisolated static let title: LocalizedStringResource = "Lock Keyboard"
  nonisolated static let description = IntentDescription(
    "Locks keyboard input, including volume, brightness, and media controls, while keeping mouse and trackpad input available."
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
  nonisolated static let description = IntentDescription(
    "Unlocks keyboard input and keyboard system controls."
  )

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
    "Returns whether keyboard input and keyboard system controls are currently locked."
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
