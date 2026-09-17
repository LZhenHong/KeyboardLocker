import AppIntents
import Foundation

@MainActor
struct LockKeyboardIntent: nonisolated AppIntent {
  nonisolated static let title: LocalizedStringResource = "Lock Keyboard"
  nonisolated static let description = IntentDescription(
    "Locks keyboard input, including volume, brightness, and media keys. Mouse and trackpad keep working."
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
struct ToggleKeyboardLockIntent: nonisolated AppIntent {
  nonisolated static let title: LocalizedStringResource = "Toggle Keyboard Lock"
  nonisolated static let description = IntentDescription(
    "Flips the keyboard lock state and returns the new state."
  )

  private let client: any AgentLockActionServing

  nonisolated init() {
    client = LiveAgentClient()
  }

  nonisolated init(client: any AgentLockActionServing) {
    self.client = client
  }

  nonisolated func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
    try await .result(value: client.toggle())
  }
}

@MainActor
struct GetKeyboardLockStatusIntent: nonisolated AppIntent {
  nonisolated static let title: LocalizedStringResource = "Get Keyboard Lock Status"
  nonisolated static let description = IntentDescription(
    "Returns whether the keyboard is currently locked."
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
