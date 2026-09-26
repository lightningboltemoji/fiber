// swift-tools-version: 6.2

// Builds //fiber/ui's sources with SwiftPM, so Xcode can open them (previews,
// editor tooling) and FiberUIHarness can run the UI against a mock browser
// without building Chromium. GN builds the same sources into the app (see
// BUILD.gn). If this builds, FiberUI doesn't depend on Chromium.
//
//   swift run --package-path core/ui FiberUIHarness

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
  ]
)
