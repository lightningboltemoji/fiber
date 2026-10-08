import AppKit
import ScreenCaptureKit

// director TAPE [--app PATH] [--rehearse]
//
// Plays TAPE on Fiber and records the take into demo/takes/<tape>/: take.mov,
// window.png (its mask) and timeline.json. --rehearse plays it without
// recording. See .agents/DEMO.md.

// ScreenCaptureKit and the window server calls need a connection to it.
_ = NSApplication.shared

var arguments = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
  guard let index = arguments.firstIndex(of: name) else {
    return false
  }
  arguments.remove(at: index)
  return true
}
func option(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
    return nil
  }
  defer { arguments.removeSubrange(index...index + 1) }
  return arguments[index + 1]
}

let app = option("--app")
let rehearse = flag("--rehearse")
guard arguments.count == 1 else {
  print("usage: director TAPE [--app PATH] [--rehearse]")
  exit(2)
}

do {
  let tapeURL = URL(filePath: arguments[0]).standardizedFileURL
  var tape = try Tape(contentsOf: tapeURL)
  if let app {
    tape.app = app
  }
  try await Director(tape: tape, tapeURL: tapeURL, record: !rehearse).run()
} catch {
  print("director: \(error)")
  exit(1)
}

@MainActor
final class Director {
  let tape: Tape
  let root: URL
  let sites: URL
  let take: URL
  let record: Bool

  private var fiber: Fiber!
  private var input: Input!
  private var devTools: DevTools?
  private var windowAX: AXElement!
  private var windowFrame = CGRect.zero
  private var start = 0.0
  /// Set once recording starts: steps before then aren't in it.
  private var timeline: Timeline?

  init(tape: Tape, tapeURL: URL, record: Bool) throws {
    self.tape = tape
    self.record = record
    var root = tapeURL.deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appending(path: "CHROMIUM_VERSION").path()) {
      guard root.pathComponents.count > 1 else {
        throw DirectorError("the tape isn't in Fiber's repo")
      }
      root = root.deletingLastPathComponent()
    }
    self.root = root
    sites = root.appending(path: "demo/sites")
    take = root.appending(path: "demo/takes/\(tape.name)")
  }

  func run() async throws {
    let bundle = tape.app.map { URL(filePath: $0, relativeTo: root) }
      ?? root.appending(path: "chromium/src/out/Release/Fiber.app")
    try? FileManager.default.removeItem(at: take)
    try FileManager.default.createDirectory(at: take, withIntermediateDirectories: true)
    let profile = take.appending(path: "profile")

    let server = SiteServer(root: sites)
    let serving = try await server.start(certificateIn: take)
    defer { server.stop() }

    if !tape.visits.isEmpty {
      print("visiting \(tape.visits.count) pages for history")
      let visit = try Fiber(bundle: bundle, profile: profile, serving: serving, urls: tape.visits)
      _ = try await visit.window()
      await waitUntilServed(tape.visits, by: server)
      try await Task.sleep(for: .seconds(2))
      await visit.quit()
    }
    try Profile.addPins(tape.pins, to: profile, sites: sites)

    let frame = try plannedFrame()
    fiber = try Fiber(
      bundle: bundle, profile: profile,
      serving: serving + [
        "--window-position=\(Int(frame.minX)),\(Int(frame.minY))",
        "--window-size=\(Int(frame.width)),\(Int(frame.height))",
      ], urls: tape.opens)
    input = Input(seed: tape.seed)
    do {
      try await play(server: server)
    } catch {
      await input.releaseModifiers()
      await fiber.quit()
      throw error
    }
    await fiber.quit()
  }

  private func play(server: SiteServer) async throws {
    let (windowID, ax) = try await fiber.window()
    windowAX = ax
    devTools = try? await DevTools.connect(profile: fiber.profile)
    await waitUntilServed(tape.opens, by: server)
    try await layOut()
    try await fiber.bringToFront()
    input.warp(to: global(tape.pointer))
    // Let the pages and the window's own opening animations finish.
    try await Task.sleep(for: .milliseconds(1500))
    for step in tape.setup {
      try await perform(step)
    }

    var recorder: Recorder?
    if record {
      var window: SCWindow?
      for _ in 0..<50 where window?.frame != windowFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        window = content.windows.first { $0.windowID == windowID }
        try await Task.sleep(for: .milliseconds(50))
      }
      guard let window, window.frame == windowFrame else {
        throw DirectorError("ScreenCaptureKit can't see Fiber's window where it is")
      }
      recorder = try Recorder(window: window, to: take.appending(path: "take.mov"), fps: tape.fps,
        showsCursor: tape.showsCursor)
      try await recorder!.snapshot(to: take.appending(path: "window.png"))
    }
    if !InputWatch.start() {
      print("warning: can't watch for your input, so touching the mouse or keyboard won't stop the take")
    }
    print(record ? "recording: hands off the mouse and keyboard" : "rehearsing")
    start = try await recorder?.start() ?? hostNow()
    timeline = Timeline(
      tape: tape.name, scale: Double(recorder.map { $0.pixelSize.width / windowFrame.width } ?? 2),
      window: .init(x: 0, y: 0, width: windowFrame.width, height: windowFrame.height), fps: tape.fps)
    input.onPointer = { [unowned self] point, pressed in
      timeline?.pointer.append(.init(
        time: hostNow() - start, x: point.x - windowFrame.minX, y: point.y - windowFrame.minY, pressed: pressed))
    }
    input.onPointer?(input.pointer, false)

    do {
      for step in tape.steps {
        if let interruption = InputWatch.interruption {
          throw DirectorError("stopped by \(interruption) at line \(step.line): run it again with your hands off")
        }
        let began = hostNow() - start
        try await perform(step)
        timeline?.steps.append(.init(line: step.line, command: step.text, start: began, end: hostNow() - start))
      }
      try await Task.sleep(for: .milliseconds(300))
    } catch {
      try? await finish(recorder)
      throw error
    }
    try await finish(recorder)
  }

  private func finish(_ recorder: Recorder?) async throws {
    let end = hostNow()
    timeline?.duration = end - start
    try await recorder?.stop(at: end)
    guard let recorder, let timeline else {
      return
    }
    try timeline.write(to: take.appending(path: "timeline.json"))
    let size = (try? take.appending(path: "take.mov").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    print(String(format: "recorded %.1fs, %d frames (%d dropped), %.0f MB, in %@", timeline.duration,
      recorder.frames, recorder.dropped, Double(size) / 1e6, take.path()))
  }

  private func waitUntilServed(_ urls: [String], by server: SiteServer) async {
    let pages = urls.compactMap { URL(string: $0) }
    for _ in 0..<150 where !pages.allSatisfy(server.hasServed) {
      try? await Task.sleep(for: .milliseconds(100))
    }
  }

  /// Where the tape's window goes: centered on the main display.
  private func plannedFrame() throws -> CGRect {
    guard let screen = NSScreen.screens.first else {
      throw DirectorError("no display")
    }
    let visible = screen.visibleFrame
    let top = screen.frame.maxY - visible.maxY
    let size = tape.window
    guard size.width <= visible.width, size.height <= visible.height else {
      throw DirectorError("a \(Int(size.width))×\(Int(size.height)) window doesn't fit on a "
        + "\(Int(visible.width))×\(Int(visible.height)) display")
    }
    return CGRect(
      x: (visible.midX - size.width / 2).rounded(), y: (top + (visible.height - size.height) / 2).rounded(),
      width: size.width, height: size.height)
  }

  /// Chrome sizes its first window again as the browser takes it over, which
  /// can be after it shows, so this sets the frame until it stays put. More
  /// than a few tries means something else is moving it.
  private func layOut() async throws {
    let frame = try plannedFrame()
    let clock = ContinuousClock()
    var steadySince = clock.now
    var tries = 0
    while clock.now - steadySince < .milliseconds(700) {
      if windowAX.frame != frame {
        guard tries < 4 else {
          throw DirectorError("something keeps moving Fiber's window (a window manager?): it's at "
            + "\(windowAX.frame ?? .zero), not \(frame)")
        }
        windowAX.setFrame(frame)
        tries += 1
        steadySince = clock.now
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    windowFrame = frame
  }

  private func global(_ point: CGPoint) -> CGPoint {
    CGPoint(x: windowFrame.minX + point.x, y: windowFrame.minY + point.y)
  }

  // MARK: Steps

  private func perform(_ step: Step) async throws {
    func fail(_ message: String) -> TapeError {
      TapeError(line: step.line, message: message)
    }
    switch step.command {
    case .sleep(let duration):
      try await Task.sleep(for: duration)
    case .type(let text, let perKey):
      try requireFront(step)
      await input.type(text, perKey: perKey)
    case .key(let combos):
      try requireFront(step)
      for (index, combo) in combos.enumerated() {
        if index > 0 {
          try await Task.sleep(for: .milliseconds(160))
        }
        timeline?.keys.append(.init(time: hostNow() - start, keys: combo.description))
        await input.press(combo)
      }
    case .hold(let combo, let duration):
      try requireFront(step)
      timeline?.keys.append(.init(time: hostNow() - start, keys: combo.description))
      await input.press(combo, hold: duration)
    case .move(let target, let duration):
      try requireFront(step)
      guard let rect = try await resolve(target) else {
        throw fail("can't find \(target)")
      }
      await input.move(to: CGPoint(x: rect.midX, y: rect.midY), over: duration)
    case .click(let target):
      try requireFront(step)
      if let target {
        guard let rect = try await resolve(target) else {
          throw fail("can't find \(target)")
        }
        await input.move(to: CGPoint(x: rect.midX, y: rect.midY), over: .milliseconds(600))
        try await Task.sleep(for: .milliseconds(120))
      }
      await input.click()
    case .scroll(let distance, let duration):
      try requireFront(step)
      await input.scroll(by: distance, over: duration)
    case .waitTitle(let text, let timeout):
      try await poll(timeout, step, "the title to have \"\(text)\"") {
        self.windowAX.title?.localizedCaseInsensitiveContains(text) == true
      }
    case .waitElement(let target, let gone, let timeout):
      try await poll(timeout, step, gone ? "\(target) to go" : "\(target)") {
        (try? await self.resolve(target)) == nil ? gone : !gone
      }
    case .waitLoad(let timeout):
      try await poll(timeout, step, "the page to load") {
        let state = try? await self.devTools?.evaluate("document.readyState", inPageTitled: self.windowAX.title)
        return state as? String == "complete"
      }
    case .mark(let name, let target):
      guard let rect = try await resolve(target) else {
        throw fail("can't find \(target) to mark")
      }
      timeline?.markers.append(.init(
        name: name, time: hostNow() - start, rect: .init(rect.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY))))
    case .tree:
      var out = "line \(step.line), window at \(windowFrame.origin):\n"
      windowAX.dump(into: &out)
      let file = take.appending(path: "tree-\(step.line).txt")
      try out.write(to: file, atomically: true, encoding: .utf8)
      print("tree at line \(step.line): \(file.path())")
    }
  }

  /// Input only goes where it's meant to while Fiber is frontmost, and its
  /// window only looks right then.
  private func requireFront(_ step: Step) throws {
    if !fiber.isFrontmost {
      throw TapeError(line: step.line, message: "Fiber isn't frontmost anymore, so the take stopped")
    }
  }

  private func poll(_ timeout: Duration, _ step: Step, _ what: String, _ check: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(await check()) {
      guard ContinuousClock.now < deadline else {
        throw TapeError(line: step.line, message: "gave up waiting for \(what)")
      }
      try await Task.sleep(for: .milliseconds(40))
    }
  }

  /// Where `target` is now, in global points.
  private func resolve(_ target: Target) async throws -> CGRect? {
    switch target {
    case .window:
      return windowFrame
    case .point(let point):
      return CGRect(origin: global(point), size: .zero)
    case .rect(let rect):
      return rect.offsetBy(dx: windowFrame.minX, dy: windowFrame.minY)
    case .element(let role, let label, let index):
      let found = windowAX.find(role: role, label: label, limit: index + 1)
      return found.count > index ? found[index].frame : nil
    case .page(let selector):
      guard let devTools else {
        throw DirectorError("DevTools isn't connected, so pages' elements can't be found")
      }
      let quoted = String(decoding: try JSONEncoder().encode(selector), as: UTF8.self)
      let expression = """
        (() => { const e = document.querySelector(\(quoted)); if (!e) return null;
          const r = e.getBoundingClientRect(); return [r.x, r.y, r.width, r.height]; })()
        """
      guard let values = try await devTools.evaluate(expression, inPageTitled: windowAX.title) as? [Double],
        values.count == 4
      else {
        return nil
      }
      return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        .offsetBy(dx: windowFrame.minX, dy: windowFrame.minY)
    }
  }
}
