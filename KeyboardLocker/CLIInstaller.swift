//
//  CLIInstaller.swift
//  KeyboardLocker
//
//  Created by Eden on 2025/12/16.
//

import AppKit
import Common
import Foundation

enum CLIInstaller {
  static var cliName: String { SharedConstants.cliName }
  static var installPath: String { SharedConstants.cliInstallPath }

  enum InstallResult {
    case success
    case alreadyInstalled
    case cancelled
    case failed(Error)
  }

  enum InstallError: LocalizedError {
    case cliNotFoundInBundle
    case scriptExecutionFailed(String)

    var errorDescription: String? {
      switch self {
      case .cliNotFoundInBundle:
        "CLI tool not found in application bundle."
      case let .scriptExecutionFailed(message):
        "Installation failed: \(message)"
      }
    }
  }

  /// Path to the CLI binary inside the app bundle
  static var cliBundlePath: String? {
    Bundle.main.path(forAuxiliaryExecutable: cliName)
  }

  /// Check if CLI is already installed at the target path
  static var isInstalled: Bool {
    FileManager.default.fileExists(atPath: installPath)
  }

  /// Check if the installed CLI points to the current app bundle
  static var isCurrentVersionInstalled: Bool {
    guard isInstalled,
          let bundlePath = cliBundlePath,
          let linkDest = try? FileManager.default.destinationOfSymbolicLink(atPath: installPath)
    else {
      return false
    }
    return linkDest == bundlePath
  }

  /// Install the CLI tool to /usr/local/bin with admin privileges
  static func install() -> InstallResult {
    guard let bundlePath = cliBundlePath else {
      return .failed(InstallError.cliNotFoundInBundle)
    }

    // If already installed and pointing to current bundle, skip
    if isCurrentVersionInstalled {
      return .alreadyInstalled
    }

    // Build the shell command
    // Remove existing symlink if present, then create new one
    let commands = [
      "mkdir -p /usr/local/bin",
      "rm -f '\(installPath)'",
      "ln -s '\(bundlePath)' '\(installPath)'",
    ]
    let script = commands.joined(separator: " && ")

    // Execute with admin privileges using AppleScript
    let appleScript = """
    do shell script "\(script)" with administrator privileges
    """

    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: appleScript) {
      scriptObject.executeAndReturnError(&error)

      if let error {
        let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        // Check if user cancelled
        if let errorNumber = error[NSAppleScript.errorNumber] as? Int,
           errorNumber == -128
        {
          return .cancelled
        }
        return .failed(InstallError.scriptExecutionFailed(message))
      }

      return .success
    }

    return .failed(InstallError.scriptExecutionFailed("Failed to create AppleScript"))
  }

  /// Uninstall the CLI tool
  static func uninstall() -> InstallResult {
    guard isInstalled else {
      return .success
    }

    let script = "rm -f '\(installPath)'"
    let appleScript = """
    do shell script "\(script)" with administrator privileges
    """

    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: appleScript) {
      scriptObject.executeAndReturnError(&error)

      if let error {
        let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        if let errorNumber = error[NSAppleScript.errorNumber] as? Int,
           errorNumber == -128
        {
          return .cancelled
        }
        return .failed(InstallError.scriptExecutionFailed(message))
      }

      return .success
    }

    return .failed(InstallError.scriptExecutionFailed("Failed to create AppleScript"))
  }
}
