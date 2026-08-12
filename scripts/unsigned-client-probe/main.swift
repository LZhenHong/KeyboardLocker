import Foundation

// Runbook probe: prove that an ad-hoc-signed (non-team) process cannot call the live Agent's
// Mach service. Compiled together with the Common module by verify-unsigned-client-refusal.sh,
// so it uses the real protocol and service name. swiftc output on arm64 is ad-hoc signed,
// which is exactly the class of client the Agent's code-signing requirement must refuse.
//
// Prints one RESULT line and exits: 0 = REFUSED, 1 = REPLIED, 2 = INDETERMINATE.

/// First outcome wins: refusal may surface as a proxy error, an interruption, and an
/// invalidation all at once, while a reply must never be overwritten by later teardown.
final class Outcome {
  private let lock = NSLock()
  private var recorded: (code: Int32, line: String)?

  func record(_ code: Int32, _ line: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard recorded == nil else {
      return false
    }
    recorded = (code, line)
    return true
  }

  func current() -> (code: Int32, line: String)? {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
}

let outcome = Outcome()
let finished = DispatchSemaphore(value: 0)

func finish(_ code: Int32, _ line: String) {
  if outcome.record(code, line) {
    finished.signal()
  }
}

let connection = NSXPCConnection(machServiceName: SharedConstants.machServiceName)
connection.remoteObjectInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
connection.invalidationHandler = {
  finish(0, "RESULT:REFUSED connection invalidated before any reply")
}

connection.interruptionHandler = {
  finish(0, "RESULT:REFUSED connection interrupted before any reply")
}

connection.activate()

guard
  let service = connection.remoteObjectProxyWithErrorHandler({ error in
    finish(0, "RESULT:REFUSED proxy error: \(error.localizedDescription)")
  }) as? KeyboardLockerServiceProtocol
else {
  print("RESULT:INDETERMINATE could not create a remote object proxy")
  exit(2)
}

// A descriptor reply proves acceptance and identifies the Agent generation if the listener's
// fail-closed requirement is broken. Refusal still surfaces before any exported selector runs.
service.serviceDescriptor { data, error in
  if let descriptor = try? ServiceDescriptor.decodedFromXPC(data) {
    finish(1, "RESULT:REPLIED \(descriptor.agentInstanceID.uuidString)")
  } else if let error {
    finish(1, "RESULT:REPLIED agent returned an error: \(error.localizedDescription)")
  } else {
    finish(1, "RESULT:REPLIED agent returned an invalid descriptor")
  }
}

if finished.wait(timeout: .now() + 10) == .timedOut {
  print("RESULT:INDETERMINATE no reply, error, or invalidation within 10s")
  exit(2)
}

guard let result = outcome.current() else {
  print("RESULT:INDETERMINATE semaphore signalled without an outcome")
  exit(2)
}

print(result.line)
exit(result.code)
