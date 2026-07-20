import Common
import Foundation

/// Monotonic `CFBundleVersion` value with arbitrary-precision dotted numeric comparison.
public struct ServiceBuildVersion: Comparable, Sendable {
  public let rawValue: String

  private let components: [String]

  public init?(_ rawValue: String) {
    let sourceComponents = rawValue.split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    guard !sourceComponents.isEmpty else {
      return nil
    }

    var normalized: [String] = []
    for component in sourceComponents {
      guard !component.isEmpty,
            component.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
      else {
        return nil
      }

      let significantDigits = component.drop(while: { $0 == "0" })
      normalized.append(significantDigits.isEmpty ? "0" : String(significantDigits))
    }

    self.rawValue = rawValue
    components = normalized
  }

  public static func == (lhs: ServiceBuildVersion, rhs: ServiceBuildVersion) -> Bool {
    compare(lhs, rhs) == 0
  }

  public static func < (lhs: ServiceBuildVersion, rhs: ServiceBuildVersion) -> Bool {
    compare(lhs, rhs) < 0
  }

  private static func compare(
    _ lhs: ServiceBuildVersion,
    _ rhs: ServiceBuildVersion
  ) -> Int {
    for index in 0..<max(lhs.components.count, rhs.components.count) {
      let left = index < lhs.components.count ? lhs.components[index] : "0"
      let right = index < rhs.components.count ? rhs.components[index] : "0"

      if left.count != right.count {
        return left.count < right.count ? -1 : 1
      }
      if left != right {
        return left < right ? -1 : 1
      }
    }
    return 0
  }
}

/// Contract and bundled identity the App requires from a running Agent.
public struct ServiceCompatibilityRequirements: Equatable, Sendable {
  public let minimumProtocolVersion: ServiceProtocolVersion
  public let requiredCapabilities: Set<ServiceCapability>
  public let agentBundleIdentifier: String
  public let agentVersion: String
  public let agentBuild: String

  public init(
    minimumProtocolVersion: ServiceProtocolVersion = ServiceContract.protocolVersion,
    requiredCapabilities: Set<ServiceCapability> = ServiceContract.requiredCapabilities,
    agentBundleIdentifier: String,
    agentVersion: String,
    agentBuild: String
  ) {
    self.minimumProtocolVersion = minimumProtocolVersion
    self.requiredCapabilities = requiredCapabilities
    self.agentBundleIdentifier = agentBundleIdentifier
    self.agentVersion = agentVersion
    self.agentBuild = agentBuild
  }
}

public enum ServiceCompatibilityIssue: Error, Equatable, LocalizedError {
  case agentBuildMismatch(expected: String, actual: String)
  case agentBundleIdentifierMismatch(expected: String, actual: String)
  case agentVersionMismatch(expected: String, actual: String)
  case missingCapabilities([ServiceCapability])
  case protocolMajorMismatch(expected: Int, actual: Int)
  case protocolMinorTooOld(required: Int, actual: Int)

  public var errorDescription: String? {
    switch self {
    case let .agentBuildMismatch(expected, actual):
      return "The running agent build is \(actual); the bundled build is \(expected)."

    case let .agentBundleIdentifierMismatch(expected, actual):
      return "The running agent identifier is \(actual); the bundled identifier is \(expected)."

    case let .agentVersionMismatch(expected, actual):
      return "The running agent version is \(actual); the bundled version is \(expected)."

    case let .missingCapabilities(capabilities):
      let names = capabilities.map(\.rawValue).sorted().joined(separator: ", ")
      return "The running agent is missing required capabilities: \(names)."

    case let .protocolMajorMismatch(expected, actual):
      return "The running agent uses XPC protocol major version \(actual); this app requires \(expected)."

    case let .protocolMinorTooOld(required, actual):
      return "The running agent uses XPC protocol minor version \(actual); this app requires at least \(required)."
    }
  }
}

public extension ServiceDescriptor {
  func compatibilityIssues(
    against requirements: ServiceCompatibilityRequirements
  ) -> [ServiceCompatibilityIssue] {
    var issues: [ServiceCompatibilityIssue] = []

    if protocolVersion.major != requirements.minimumProtocolVersion.major {
      issues.append(.protocolMajorMismatch(
        expected: requirements.minimumProtocolVersion.major,
        actual: protocolVersion.major
      ))
    } else if protocolVersion.minor < requirements.minimumProtocolVersion.minor {
      issues.append(.protocolMinorTooOld(
        required: requirements.minimumProtocolVersion.minor,
        actual: protocolVersion.minor
      ))
    }

    let missingCapabilities = requirements.requiredCapabilities.subtracting(capabilities)
    if !missingCapabilities.isEmpty {
      issues.append(.missingCapabilities(missingCapabilities.sorted {
        $0.rawValue < $1.rawValue
      }))
    }

    if agentBundleIdentifier != requirements.agentBundleIdentifier {
      issues.append(.agentBundleIdentifierMismatch(
        expected: requirements.agentBundleIdentifier,
        actual: agentBundleIdentifier
      ))
    }
    if agentVersion != requirements.agentVersion {
      issues.append(.agentVersionMismatch(
        expected: requirements.agentVersion,
        actual: agentVersion
      ))
    }
    if agentBuild != requirements.agentBuild {
      issues.append(.agentBuildMismatch(
        expected: requirements.agentBuild,
        actual: agentBuild
      ))
    }

    return issues
  }

  func validateCompatibility(
    against requirements: ServiceCompatibilityRequirements
  ) throws {
    if let issue = compatibilityIssues(against: requirements).first {
      throw issue
    }
  }
}
