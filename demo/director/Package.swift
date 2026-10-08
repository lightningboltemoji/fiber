// swift-tools-version: 6.2

// The director: plays a tape (demo/tapes/*.tape) on the real app and records
// the take that demo/studio cuts into a video. See .agents/DEMO.md.
//
//   swift run --package-path demo/director director demo/tapes/readme.tape

import PackageDescription

let package = Package(
  name: "Director",
  platforms: [.macOS(.v26)],
  targets: [
    .executableTarget(
      name: "director", swiftSettings: [.swiftLanguageMode(.v5)])
  ]
)
