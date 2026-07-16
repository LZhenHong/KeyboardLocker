import Common
import Foundation
import Security

/// Validates XPC connections by verifying code signature and bundle identifier.
///
/// - **Release**: Full verification (signature + Agent Team ID + bundle ID allowlist)
/// - **Debug**: Relaxed verification (bundle ID allowlist only)
public enum XPCAccessControl {
  #if !DEBUG
    /// Reads the Agent's signing Team ID from the running process so code-signing configuration
    /// remains the single source of truth.
    private static let agentTeamID: String? = {
      guard let staticCode = staticCodeForCurrentProcess(),
            SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess,
            let info = signingInfo(for: staticCode)
      else {
        return nil
      }
      return teamIdentifier(from: info)
    }()
  #endif

  /// Returns true if the connection passes security checks.
  public static func isConnectionAuthorized(_ connection: NSXPCConnection) -> Bool {
    guard let staticCode = staticCode(for: connection) else {
      return false
    }

    #if !DEBUG
      // Release: Validate signature integrity
      guard SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess else {
        return false
      }
    #endif

    guard let info = signingInfo(for: staticCode),
          let bundleID = info[kSecCodeInfoIdentifier] as? String,
          SharedConstants.authorizedClientBundleIdentifiers.contains(bundleID)
    else {
      return false
    }

    #if !DEBUG
      // Release: Require the client to be signed by the same team as the Agent.
      guard let agentTeamID = Self.agentTeamID,
            teamIdentifier(from: info) == agentTeamID
      else {
        return false
      }
    #endif

    return true
  }

  // MARK: - Private Helpers

  private static func staticCode(for connection: NSXPCConnection) -> SecStaticCode? {
    let attributes: [CFString: Any] = [kSecGuestAttributePid: connection.processIdentifier]

    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, SecCSFlags(), &code) == errSecSuccess,
          let code
    else {
      return nil
    }

    return staticCode(for: code)
  }

  private static func staticCodeForCurrentProcess() -> SecStaticCode? {
    var code: SecCode?
    guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
      return nil
    }

    return staticCode(for: code)
  }

  private static func staticCode(for code: SecCode) -> SecStaticCode? {
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess else {
      return nil
    }
    return staticCode
  }

  private static func signingInfo(for staticCode: SecStaticCode) -> [CFString: Any]? {
    var info: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess else {
      return nil
    }
    return info as? [CFString: Any]
  }

  private static func teamIdentifier(from info: [CFString: Any]) -> String? {
    info[kSecCodeInfoTeamIdentifier] as? String
  }
}
