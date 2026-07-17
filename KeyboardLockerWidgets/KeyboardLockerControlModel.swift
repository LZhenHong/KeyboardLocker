import Foundation

struct KeyboardLockerControlValueLoader: Sendable {
  typealias FetchValue = @Sendable () async throws -> Bool

  private let fetchValue: FetchValue

  init(fetchValue: @escaping FetchValue) {
    self.fetchValue = fetchValue
  }

  func currentValue() async throws -> Bool {
    try await fetchValue()
  }
}

struct KeyboardLockerControlAction: Sendable {
  typealias Operation = @Sendable () async throws -> Void
  typealias Reload = @Sendable () async -> Void

  private let lock: Operation
  private let unlock: Operation
  private let reload: Reload

  init(
    lock: @escaping Operation,
    unlock: @escaping Operation,
    reload: @escaping Reload
  ) {
    self.lock = lock
    self.unlock = unlock
    self.reload = reload
  }

  func setLocked(_ isLocked: Bool) async throws {
    if isLocked {
      try await lock()
    } else {
      try await unlock()
    }

    await reload()
  }
}
