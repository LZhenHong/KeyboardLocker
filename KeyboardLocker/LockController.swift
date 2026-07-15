import Client
import Combine
import Foundation

/// Observable view state for the lock. A thin wrapper: it holds no lock logic and no settings —
/// it issues one-off XPC calls and reflects the Agent's broadcast state, never inferring state
/// from whether a call succeeded.
@MainActor
final class LockController: ObservableObject {
  @Published private(set) var isLocked = false
  @Published private(set) var lastError: String?

  private var stateToken: ObserverToken?

  init() {
    stateToken = LockStateSubscriber.subscribe { [weak self] locked in
      // Subscriber delivers on the main queue.
      self?.isLocked = locked
    }
    Task { await refresh() }
  }

  func refresh() async {
    do {
      isLocked = try await XPCClient.shared.status()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func toggle() {
    Task {
      do {
        if isLocked {
          try await XPCClient.shared.unlock()
        } else {
          try await XPCClient.shared.lock()
        }
        lastError = nil
      } catch {
        lastError = error.localizedDescription
      }
      // State itself arrives via the broadcast subscription, not from this call's success.
    }
  }
}
