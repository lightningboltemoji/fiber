import Foundation

/// Just enough of the DevTools protocol to ask the active tab's page
/// something: where an element is, whether it has loaded.
struct DevTools {
  let port: Int

  /// The port Chrome picked for `--remote-debugging-port=0`, from the profile.
  static func connect(profile: URL, timeout: Duration = .seconds(15)) async throws -> DevTools {
    let file = profile.appending(path: "DevToolsActivePort")
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if let text = try? String(contentsOf: file, encoding: .utf8),
        let port = text.split(separator: "\n").first.flatMap({ Int($0) })
      {
        return DevTools(port: port)
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw DirectorError("DevTools never started (no \(file.path()))")
  }

  /// Evaluates `expression` in the page whose title is `title` (the window
  /// shows the active tab's), or the first page.
  func evaluate(_ expression: String, inPageTitled title: String?) async throws -> Any? {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/json/list")!)
    let targets = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? [])
      .filter { $0["type"] as? String == "page" }
    guard let target = targets.first(where: { $0["title"] as? String == title }) ?? targets.first,
      let socketURL = (target["webSocketDebuggerUrl"] as? String).flatMap(URL.init(string:))
    else {
      throw DirectorError("no page to evaluate in")
    }
    let socket = URLSession.shared.webSocketTask(with: socketURL)
    socket.resume()
    defer { socket.cancel(with: .normalClosure, reason: nil) }
    let message: [String: Any] = [
      "id": 1, "method": "Runtime.evaluate",
      "params": ["expression": expression, "returnByValue": true, "awaitPromise": true],
    ]
    let body = try JSONSerialization.data(withJSONObject: message)
    try await socket.send(.string(String(decoding: body, as: UTF8.self)))
    while true {
      guard case .string(let text) = try await socket.receive(),
        let reply = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
        reply["id"] as? Int == 1
      else {
        continue
      }
      let result = (reply["result"] as? [String: Any])?["result"] as? [String: Any]
      return result?["value"]
    }
  }
}
