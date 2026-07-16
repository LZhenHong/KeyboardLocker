import Common
import Foundation

/// Creates the OS-enforced requirement for clients of the Agent's Mach service.
public enum XPCAccessControl {
  public static func authorizedClientRequirement() throws -> String {
    try XPCCodeSigningRequirement.sameTeam(
      identifiers: SharedConstants.authorizedClientBundleIdentifiers
    )
  }
}
