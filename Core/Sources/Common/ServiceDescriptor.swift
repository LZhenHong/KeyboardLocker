import Foundation

/// Version of the XPC method contract implemented by an Agent.
///
/// A major version change is breaking. Minor versions may only add selectors or behavior, and
/// clients must still check capabilities before invoking an optional selector.
public struct ServiceProtocolVersion: Codable, Equatable, Hashable, Sendable {
  public let major: Int
  public let minor: Int

  public init(major: Int, minor: Int) {
    self.major = major
    self.minor = minor
  }
}

/// Stable string capability carried by `ServiceDescriptor`.
///
/// This is intentionally not an enum: older clients must preserve and ignore capability names
/// introduced by newer Agents instead of failing to decode the descriptor.
public struct ServiceCapability: Codable, Equatable, Hashable, RawRepresentable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static let accessibilityPrompt = Self(rawValue: "accessibility-prompt")
  public static let accessibilityStatus = Self(rawValue: "accessibility-status")
  public static let currentSettings = Self(rawValue: "current-settings")
  public static let currentSettingsWithError = Self(
    rawValue: "current-settings-with-error"
  )
  public static let committedReplacementDrain = Self(
    rawValue: "committed-replacement-drain"
  )
  public static let lockControl = Self(rawValue: "lock-control")
  public static let prepareForReplacement = Self(rawValue: "prepare-for-replacement")
}

/// Additive replacement phase exposed for recovery without revealing the ownership ticket.
public struct ServiceReplacementPhase: Codable, Equatable, RawRepresentable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static let committed = Self(rawValue: "committed")
  public static let inactive = Self(rawValue: "inactive")
  public static let prepared = Self(rawValue: "prepared")
  public static let unknown = Self(rawValue: "unknown")
}

/// Current bootstrap contract advertised by the bundled Agent.
public enum ServiceContract {
  public static let protocolVersion = ServiceProtocolVersion(major: 1, minor: 2)

  public static let requiredCapabilities: Set<ServiceCapability> = [
    .accessibilityPrompt,
    .accessibilityStatus,
    .committedReplacementDrain,
    .currentSettings,
    .currentSettingsWithError,
    .lockControl,
    .prepareForReplacement,
  ]
}

/// Process-scoped description of the Agent behind an XPC connection.
///
/// Version and build metadata are compatibility diagnostics, not peer authentication. The XPC
/// connection's code-signing requirement remains the security boundary.
public struct ServiceDescriptor: Codable, Equatable, Sendable {
  public let protocolVersion: ServiceProtocolVersion
  public let capabilities: Set<ServiceCapability>
  public let agentBundleIdentifier: String
  public let agentVersion: String
  public let agentBuild: String
  public let agentInstanceID: UUID
  public let replacementPending: Bool
  public let replacementPhase: ServiceReplacementPhase

  public init(
    protocolVersion: ServiceProtocolVersion,
    capabilities: Set<ServiceCapability>,
    agentBundleIdentifier: String,
    agentVersion: String,
    agentBuild: String,
    agentInstanceID: UUID,
    replacementPending: Bool = false,
    replacementPhase: ServiceReplacementPhase = .inactive
  ) {
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities
    self.agentBundleIdentifier = agentBundleIdentifier
    self.agentVersion = agentVersion
    self.agentBuild = agentBuild
    self.agentInstanceID = agentInstanceID
    self.replacementPending = replacementPending || replacementPhase != .inactive
    self.replacementPhase = replacementPhase
  }

  private enum CodingKeys: String, CodingKey {
    case agentBuild
    case agentBundleIdentifier
    case agentInstanceID
    case agentVersion
    case capabilities
    case protocolVersion
    case replacementPending
    case replacementPhase
  }

  /// Bootstrap fields are decoded explicitly so additive fields can default when an older Agent
  /// omits them. Existing required keys and their types must remain stable for this Mach service.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    protocolVersion = try container.decode(ServiceProtocolVersion.self, forKey: .protocolVersion)
    capabilities = try container.decode(Set<ServiceCapability>.self, forKey: .capabilities)
    agentBundleIdentifier = try container.decode(String.self, forKey: .agentBundleIdentifier)
    agentVersion = try container.decode(String.self, forKey: .agentVersion)
    agentBuild = try container.decode(String.self, forKey: .agentBuild)
    agentInstanceID = try container.decode(UUID.self, forKey: .agentInstanceID)
    let decodedReplacementPending = try container.decodeIfPresent(
      Bool.self,
      forKey: .replacementPending
    ) ?? false
    let decodedReplacementPhase = try container.decodeIfPresent(
      ServiceReplacementPhase.self,
      forKey: .replacementPhase
    ) ?? (decodedReplacementPending ? .unknown : .inactive)
    replacementPending = decodedReplacementPending || decodedReplacementPhase != .inactive
    replacementPhase = decodedReplacementPhase
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(protocolVersion, forKey: .protocolVersion)
    try container.encode(capabilities, forKey: .capabilities)
    try container.encode(agentBundleIdentifier, forKey: .agentBundleIdentifier)
    try container.encode(agentVersion, forKey: .agentVersion)
    try container.encode(agentBuild, forKey: .agentBuild)
    try container.encode(agentInstanceID, forKey: .agentInstanceID)
    try container.encode(replacementPending, forKey: .replacementPending)
    try container.encode(replacementPhase, forKey: .replacementPhase)
  }
}

/// Opaque ownership token for a fail-safe Agent replacement barrier.
public struct ServiceReplacementTicket: Codable, Equatable, Sendable {
  public let id: UUID
  public let agentInstanceID: UUID

  public init(id: UUID, agentInstanceID: UUID) {
    self.id = id
    self.agentInstanceID = agentInstanceID
  }
}

/// Ticket-specific replacement state used to recover an unknown commit reply.
public struct ServiceReplacementStatus: Codable, Equatable, Sendable {
  public let phase: ServiceReplacementPhase

  public init(phase: ServiceReplacementPhase) {
    self.phase = phase
  }
}

public enum ServiceDescriptorCodingError: Error, LocalizedError {
  case missingPayload
  case payloadTooLarge
  case invalidPayload

  public var errorDescription: String? {
    switch self {
    case .missingPayload:
      "The KeyboardLocker agent returned no service descriptor."
    case .payloadTooLarge:
      "The KeyboardLocker agent returned an oversized service descriptor."
    case .invalidPayload:
      "The KeyboardLocker agent returned an invalid service descriptor."
    }
  }
}

public enum ServiceReplacementTicketCodingError: Error, LocalizedError {
  case invalidPayload
  case missingPayload
  case payloadTooLarge

  public var errorDescription: String? {
    switch self {
    case .invalidPayload:
      "The KeyboardLocker agent returned an invalid replacement ticket."
    case .missingPayload:
      "The KeyboardLocker agent returned no replacement ticket."
    case .payloadTooLarge:
      "The KeyboardLocker agent returned an oversized replacement ticket."
    }
  }
}

public enum ServiceReplacementStatusCodingError: Error, LocalizedError {
  case invalidPayload
  case missingPayload
  case payloadTooLarge

  public var errorDescription: String? {
    switch self {
    case .invalidPayload:
      "The KeyboardLocker agent returned an invalid replacement status."
    case .missingPayload:
      "The KeyboardLocker agent returned no replacement status."
    case .payloadTooLarge:
      "The KeyboardLocker agent returned an oversized replacement status."
    }
  }
}

// MARK: - XPC Serialization

public extension ServiceDescriptor {
  static let maximumEncodedSize = 16 * 1024

  func encodedForXPC() throws -> Data {
    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumEncodedSize else {
      throw ServiceDescriptorCodingError.payloadTooLarge
    }
    return data
  }

  static func decodedFromXPC(_ data: Data?) throws -> ServiceDescriptor {
    guard let data else {
      throw ServiceDescriptorCodingError.missingPayload
    }
    guard data.count <= maximumEncodedSize else {
      throw ServiceDescriptorCodingError.payloadTooLarge
    }
    do {
      return try JSONDecoder().decode(ServiceDescriptor.self, from: data)
    } catch {
      throw ServiceDescriptorCodingError.invalidPayload
    }
  }
}

public extension ServiceReplacementTicket {
  static let maximumEncodedSize = 4 * 1024

  func encodedForXPC() throws -> Data {
    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumEncodedSize else {
      throw ServiceReplacementTicketCodingError.payloadTooLarge
    }
    return data
  }

  static func decodedFromXPC(_ data: Data?) throws -> ServiceReplacementTicket {
    guard let data else {
      throw ServiceReplacementTicketCodingError.missingPayload
    }
    guard data.count <= maximumEncodedSize else {
      throw ServiceReplacementTicketCodingError.payloadTooLarge
    }
    do {
      return try JSONDecoder().decode(ServiceReplacementTicket.self, from: data)
    } catch {
      throw ServiceReplacementTicketCodingError.invalidPayload
    }
  }
}

public extension ServiceReplacementStatus {
  static let maximumEncodedSize = 4 * 1024

  func encodedForXPC() throws -> Data {
    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumEncodedSize else {
      throw ServiceReplacementStatusCodingError.payloadTooLarge
    }
    return data
  }

  static func decodedFromXPC(_ data: Data?) throws -> ServiceReplacementStatus {
    guard let data else {
      throw ServiceReplacementStatusCodingError.missingPayload
    }
    guard data.count <= maximumEncodedSize else {
      throw ServiceReplacementStatusCodingError.payloadTooLarge
    }
    do {
      return try JSONDecoder().decode(ServiceReplacementStatus.self, from: data)
    } catch {
      throw ServiceReplacementStatusCodingError.invalidPayload
    }
  }
}
