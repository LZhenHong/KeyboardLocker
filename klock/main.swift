//
//  main.swift
//  klock
//
//  Created by Eden on 2025/11/19.
//

import Core
import Foundation

let xpcClient = XPCClient.shared
let commandLineArgs = CommandLine.arguments

guard commandLineArgs.count > 1 else {
  print("Usage: klock <lock|unlock|status>")
  exit(1)
}

let semaphore = DispatchSemaphore(value: 0)

func handleResult(_ error: Error?, successMessage: String) {
  if let error {
    print("Error: \(error.localizedDescription)")
    exit(1)
  }
  print(successMessage)
  semaphore.signal()
}

switch commandLineArgs[1] {
case "lock":
  xpcClient.lock { error in
    handleResult(error, successMessage: "Locked")
  }

case "unlock":
  xpcClient.unlock { error in
    handleResult(error, successMessage: "Unlocked")
  }

case "status":
  xpcClient.status { isLocked, error in
    if let error {
      print("Error: \(error.localizedDescription)")
      exit(1)
    }
    print(isLocked ? "Locked" : "Unlocked")
    semaphore.signal()
  }

default:
  print("Unknown command: \(commandLineArgs[1])")
  exit(1)
}

semaphore.wait()
