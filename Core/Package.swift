// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "Core",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    .library(name: "Common", targets: ["Common"]),
    .library(name: "Client", targets: ["Client"]),
    .library(name: "Service", targets: ["Service"]),
    .library(name: "SystemSurfaces", targets: ["SystemSurfaces"]),
  ],
  targets: [
    .target(name: "Common"),
    .target(name: "Client", dependencies: ["Common"]),
    .target(name: "Service", dependencies: ["Common"]),
    .target(name: "SystemSurfaces"),
    .testTarget(name: "CommonTests", dependencies: ["Common"]),
    .testTarget(name: "ClientTests", dependencies: ["Client"]),
    .testTarget(name: "ServiceTests", dependencies: ["Service"]),
    .testTarget(name: "SystemSurfacesTests", dependencies: ["SystemSurfaces"]),
  ]
)
