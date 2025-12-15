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
  ],
  targets: [
    .target(name: "Common"),
    .target(name: "Client", dependencies: ["Common"]),
    .target(name: "Service", dependencies: ["Common"]),
  ]
)
