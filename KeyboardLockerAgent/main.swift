import Core
import Foundation

// Main entry point
let listener = NSXPCListener(machServiceName: SharedConstants.machServiceName)
let delegate = ServiceDelegate()
listener.delegate = delegate
listener.resume()
print("KeyboardLockerAgent started, listening on \(SharedConstants.machServiceName)")
RunLoop.main.run()
