import Common
import Foundation
import Security

/// Validates XPC connections by verifying code signature and bundle identifier.
///
/// - **Release**: Full verification (signature + Team ID + bundle ID allowlist)
/// - **Debug**: Relaxed verification (bundle ID allowlist only)
public enum XPCAccessControl {
  /// Apple Developer Team ID for certificate verification (Release only)
  private static let expectedTeamID = "SBLX9H66X2"

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
      // Release: Verify Team ID
      guard extractTeamID(from: info) == expectedTeamID else {
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

  private static func extractTeamID(from info: [CFString: Any]) -> String? {
    if let teamID = info[kSecCodeInfoTeamIdentifier] as? String {
      return teamID
    }

    // Fallback: Parse from certificate Common Name
    guard let certs = info[kSecCodeInfoCertificates] as? [SecCertificate],
          let leafCert = certs.first
    else {
      return nil
    }

    var commonName: CFString?
    SecCertificateCopyCommonName(leafCert, &commonName)

    // Extract Team ID from "Developer Name (TEAMID)" format
    if let name = commonName as String?,
       let match = name.range(of: #"\(([A-Z0-9]{10})\)$"#, options: .regularExpression)
    {
      let start = name.index(match.lowerBound, offsetBy: 1)
      let end = name.index(match.upperBound, offsetBy: -1)
      return String(name[start..<end])
    }

    return nil
  }
}
