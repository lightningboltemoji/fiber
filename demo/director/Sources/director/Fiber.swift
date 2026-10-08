import AppKit
import Foundation

struct DirectorError: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) {
    self.description = description
  }
}

/// A run of the app on the take's own profile.
@MainActor
final class Fiber {
  let process = Process()
  let profile: URL

  var pid: pid_t { process.processIdentifier }
  var app: AXElement { .application(pid) }

  /// Starts the app at `bundle` with `urls` as its first window's tabs, with
  /// `serving`, the site server's flags.
  init(bundle: URL, profile: URL, serving: [String], urls: [String]) throws {
    self.profile = profile
    let name = bundle.deletingPathExtension().lastPathComponent
    process.executableURL = bundle.appending(path: "Contents/MacOS/\(name)")
    process.arguments = [
      "--user-data-dir=\(profile.path())",
      "--no-first-run",
      "--no-default-browser-check",
      "--use-mock-keychain",
      "--remote-debugging-port=0",
      "--disable-background-networking",
    ] + serving + urls
    process.standardOutput = FileHandle.nullDevice
    let log = profile.deletingLastPathComponent().appending(path: "fiber.log")
    FileManager.default.createFile(atPath: log.path(), contents: nil)
    process.standardError = try FileHandle(forWritingTo: log)
    try process.run()
  }

  /// Quits as the Dock's Quit does, which saves the profile (a SIGTERM
  /// exits without writing history); kills it if that takes too long.
  func quit() async {
    guard process.isRunning else {
      return
    }
    NSRunningApplication(processIdentifier: pid)?.terminate()
    for _ in 0..<100 where process.isRunning {
      try? await Task.sleep(for: .milliseconds(100))
    }
    if process.isRunning {
      kill(pid, SIGKILL)
    }
  }

  /// The browser window: the app's largest, since Chrome also keeps a hidden
  /// 500×500 one and a few short ones.
  func window(timeout: Duration = .seconds(20)) async throws -> (id: CGWindowID, ax: AXElement) {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
      let ours = windows.filter { $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0 }
      let largest = ours.max { area($0) < area($1) }
      if let largest, area(largest) > 300 * 300,
        let id = largest[kCGWindowNumber as String] as? CGWindowID,
        let ax = app.find(role: "AXWindow", label: nil, limit: 4).max(by: { ($0.frame?.width ?? 0) < ($1.frame?.width ?? 0) })
      {
        return (id, ax)
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw DirectorError("Fiber's window never showed")
  }

  private func area(_ info: [String: Any]) -> Double {
    guard let bounds = info[kCGWindowBounds as String] as? [String: Double] else {
      return 0
    }
    return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
  }

  var isFrontmost: Bool {
    (app.value(kAXFrontmostAttribute) as? Bool) == true
  }

  /// Brings the app to the front through AX, which unlike activating it from
  /// another app isn't something the system can decline.
  func bringToFront() async throws {
    for _ in 0..<10 {
      if isFrontmost {
        return
      }
      app.set(kAXFrontmostAttribute, kCFBooleanTrue)
      try await Task.sleep(for: .milliseconds(150))
    }
    throw DirectorError("couldn't bring Fiber to the front")
  }
}

/// The take's profile: what Fiber would have after `visits`, with `pins`.
enum Profile {
  /// Pins as PinStore keeps them in Preferences, each with its site's
  /// favicon.svg as the icon it last saw.
  static func addPins(_ pins: [(url: String, title: String)], to profile: URL, sites: URL) throws {
    let file = profile.appending(path: "Default/Preferences")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    var preferences = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]) ?? [:]
    var fiber = preferences["fiber"] as? [String: Any] ?? [:]
    fiber["pins"] = pins.map { pin -> [String: String] in
      let host = URL(string: pin.url)?.host() ?? ""
      let icon = favicon(at: sites.appending(path: "\(host)/favicon.svg"))
      return ["id": UUID().uuidString.lowercased(), "url": pin.url, "title": pin.title,
              "icon": icon?.base64EncodedString() ?? ""]
    }
    preferences["fiber"] = fiber
    // Open a new tab page at startup, not the last session (the visits').
    var session = preferences["session"] as? [String: Any] ?? [:]
    session["restore_on_startup"] = 5
    preferences["session"] = session
    try JSONSerialization.data(withJSONObject: preferences).write(to: file)
    try? FileManager.default.removeItem(at: profile.appending(path: "Default/Sessions"))
  }

  /// A 64-pixel PNG of an SVG favicon.
  private static func favicon(at url: URL) -> Data? {
    guard let image = NSImage(contentsOf: url) else {
      return nil
    }
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
  }
}
