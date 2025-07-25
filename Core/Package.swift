// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "Core",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "Core", targets: ["Core"]),
  ],
  targets: [
    .target(name: "Core"),
  ]
)
