import Foundation

// Positive control for verify-unsigned-client-refusal.sh. The script signs this temporary binary
// with the same local identity and exact signing identifier as the bundled klock executable. A
// decoded descriptor proves that an authorized client reached the authenticated live Agent.

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

let agentRequirement: String
do {
  agentRequirement = try XPCCodeSigningRequirement.sameTeam(
    identifiers: [SharedConstants.agentBundleIdentifier]
  )
} catch {
  print("RESULT:INDETERMINATE could not construct the Agent requirement: \(error)")
  exit(2)
}

let connection = NSXPCConnection(machServiceName: SharedConstants.machServiceName)
connection.remoteObjectInterface = NSXPCInterface(with: KeyboardLockerServiceProtocol.self)
connection.setCodeSigningRequirement(agentRequirement)
connection.invalidationHandler = {
  finish(2, "RESULT:INDETERMINATE authorized connection invalidated before any reply")
}

connection.interruptionHandler = {
  finish(2, "RESULT:INDETERMINATE authorized connection interrupted before any reply")
}

connection.activate()

guard
  let service = connection.remoteObjectProxyWithErrorHandler({ error in
    finish(2, "RESULT:INDETERMINATE authorized proxy error: \(error.localizedDescription)")
  }) as? KeyboardLockerServiceProtocol
else {
  print("RESULT:INDETERMINATE could not create an authorized remote object proxy")
  exit(2)
}

service.serviceDescriptor { data, error in
  if let error {
    finish(2, "RESULT:INDETERMINATE Agent returned an error: \(error.localizedDescription)")
    return
  }

  do {
    let descriptor = try ServiceDescriptor.decodedFromXPC(data)
    guard descriptor.agentBundleIdentifier == SharedConstants.agentBundleIdentifier else {
      finish(
        2,
        "RESULT:INDETERMINATE unexpected Agent identifier: \(descriptor.agentBundleIdentifier)"
      )
      return
    }
    finish(0, "RESULT:LIVE \(descriptor.agentInstanceID.uuidString)")
  } catch {
    finish(2, "RESULT:INDETERMINATE invalid Agent descriptor: \(error.localizedDescription)")
  }
}

if finished.wait(timeout: .now() + 10) == .timedOut {
  print("RESULT:INDETERMINATE authorized Agent did not respond within 10s")
  exit(2)
}

guard let result = outcome.current() else {
  print("RESULT:INDETERMINATE semaphore signalled without an outcome")
  exit(2)
}

print(result.line)
exit(result.code)
