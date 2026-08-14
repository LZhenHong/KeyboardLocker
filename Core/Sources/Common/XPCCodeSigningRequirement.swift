import Foundation
import Security

/// Builds OS-enforced XPC peer requirements from the current process's signing identity.
///
/// Every KeyboardLocker executable derives the Team ID from its own validated signature. This
/// keeps signing configuration as the source of truth while still requiring an exact peer
/// identifier. Unsigned and ad-hoc processes fail closed because they have no Apple Team ID.
public enum XPCCodeSigningRequirement {
  public static func sameTeam(
    identifiers: Set<String>
  ) throws -> String {
    try make(
      teamIdentifier: currentProcessTeamIdentifier(),
      identifiers: identifiers
    )
  }

  static func make(
    teamIdentifier: String,
    identifiers: Set<String>
  ) throws -> String {
    guard teamIdentifier.utf8.count == 10,
          teamIdentifier.utf8.allSatisfy(isUppercaseLetterOrDigit)
    else {
      throw XPCCodeSigningRequirementError.invalidTeamIdentifier
    }
    guard !identifiers.isEmpty else {
      throw XPCCodeSigningRequirementError.missingSigningIdentifier
    }

    let identifierClauses = try identifiers.sorted().map { identifier in
      guard !identifier.isEmpty,
            identifier.utf8.allSatisfy(Self.isIdentifierCharacter)
      else {
        throw XPCCodeSigningRequirementError.invalidSigningIdentifier(identifier)
      }
      return #"identifier "\#(identifier)""#
    }

    let requirement = """
    anchor apple generic and certificate leaf[subject.OU] = "\(teamIdentifier)" and \
    (\(identifierClauses.joined(separator: " or ")))
    """

    var compiledRequirement: SecRequirement?
    let status = SecRequirementCreateWithString(
      requirement as CFString,
      SecCSFlags(),
      &compiledRequirement
    )
    guard status == errSecSuccess, compiledRequirement != nil else {
      throw XPCCodeSigningRequirementError.invalidRequirement(status)
    }

    return requirement
  }

  private static func currentProcessTeamIdentifier() throws -> String {
    var code: SecCode?
    let copyStatus = SecCodeCopySelf(SecCSFlags(), &code)
    guard copyStatus == errSecSuccess, let code else {
      throw XPCCodeSigningRequirementError.currentProcessSignatureUnavailable(copyStatus)
    }

    let validityStatus = SecCodeCheckValidity(code, SecCSFlags(), nil)
    guard validityStatus == errSecSuccess else {
      throw XPCCodeSigningRequirementError.currentProcessSignatureInvalid(validityStatus)
    }

    var staticCode: SecStaticCode?
    let staticCodeStatus = SecCodeCopyStaticCode(
      code,
      SecCSFlags(),
      &staticCode
    )
    guard staticCodeStatus == errSecSuccess, let staticCode else {
      throw XPCCodeSigningRequirementError.currentProcessSignatureUnavailable(staticCodeStatus)
    }

    var information: CFDictionary?
    let informationStatus = SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &information
    )
    guard informationStatus == errSecSuccess,
          let dictionary = information as? [CFString: Any],
          let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier] as? String
    else {
      throw XPCCodeSigningRequirementError.missingTeamIdentifier
    }
    return teamIdentifier
  }

  private static func isUppercaseLetterOrDigit(_ byte: UInt8) -> Bool {
    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
  }

  private static func isIdentifierCharacter(_ byte: UInt8) -> Bool {
    isUppercaseLetterOrDigit(byte)
      || (byte >= 97 && byte <= 122)
      || byte == 45
      || byte == 46
  }
}

enum XPCCodeSigningRequirementError: Error, LocalizedError {
  case currentProcessSignatureInvalid(OSStatus)
  case currentProcessSignatureUnavailable(OSStatus)
  case invalidRequirement(OSStatus)
  case invalidSigningIdentifier(String)
  case invalidTeamIdentifier
  case missingSigningIdentifier
  case missingTeamIdentifier

  var errorDescription: String? {
    switch self {
    case let .currentProcessSignatureInvalid(status):
      "The current process has an invalid code signature (OSStatus \(status))."

    case let .currentProcessSignatureUnavailable(status):
      "The current process code signature is unavailable (OSStatus \(status))."

    case let .invalidRequirement(status):
      "The XPC code-signing requirement is invalid (OSStatus \(status))."

    case let .invalidSigningIdentifier(identifier):
      "The XPC signing identifier is invalid: \(identifier)."

    case .invalidTeamIdentifier:
      "The current process has an invalid Apple Team ID."

    case .missingSigningIdentifier:
      "The XPC code-signing requirement has no allowed identifier."

    case .missingTeamIdentifier:
      "The current process is not signed with an Apple Team ID."
    }
  }
}
