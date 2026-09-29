// swift-tools-version: 6.2

// Builds //fiber/ui's sources with SwiftPM, for Xcode (previews, editor
// tooling), for FiberUIHarness to run the UI against a mock browser, for its
// tests, and to prove the UI doesn't depend on Chromium. GN builds them into
// the app.
//
//   swift run --package-path core/ui FiberUIHarness
//   swift test --package-path core/ui

import PackageDescription

let package = Package(
  name: "FiberUI",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "FiberUI", targets: ["FiberUI"]),
    .executable(name: "FiberUIHarness", targets: ["FiberUIHarness"]),
  ],
  targets: [
    // //fiber/bridge's headers: Sources/FiberBridge links to
    // ../../bridge/include, which has the module map.
    .systemLibrary(name: "FiberBridge", path: "Sources/FiberBridge"),
    .target(name: "FiberUI", dependencies: ["FiberBridge"]),
    .executableTarget(
      name: "FiberUIHarness", dependencies: ["FiberBridge", "FiberUI"]),
    .testTarget(name: "FiberUITests", dependencies: ["FiberUI"]),
  ]
)
