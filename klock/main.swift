//
//  main.swift
//  klock
//
//  Created by Eden on 2025/11/19.
//

import Core
import Foundation

let client = XPCClient.shared
let args = CommandLine.arguments

guard args.count > 1 else {
  print("Usage: klock <lock|unlock|status>")
  exit(1)
}

let command = args[1]
let semaphore = DispatchSemaphore(value: 0)

switch command {
case "lock":
  client.lock { error in
    if let error {
      print("Error: \(error.localizedDescription)")
      exit(1)
    }
    print("Locked")
    semaphore.signal()
  }

case "unlock":
  client.unlock { error in
    if let error {
      print("Error: \(error.localizedDescription)")
      exit(1)
    }
    print("Unlocked")
    semaphore.signal()
  }

case "status":
  client.status { isLocked, error in
    if let error {
      print("Error: \(error.localizedDescription)")
      exit(1)
    }
    print(isLocked ? "Locked" : "Unlocked")
    semaphore.signal()
  }

default:
  print("Unknown command: \(command)")
  exit(1)
}

semaphore.wait()
