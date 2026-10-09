import Foundation

/// Just enough of the DevTools protocol to ask a page something (where an
/// element is, whether it has loaded) and to hold an override on it.
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

  /// Opens `url` in a new tab, which unlike the command line can be any of
  /// Chrome's own pages.
  func open(_ url: String) async throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/json/new?\(url)")!)
    request.httpMethod = "PUT"
    _ = try await URLSession.shared.data(for: request)
  }

  /// Evaluates `expression` in the page whose title is `title` (the window
  /// shows the active tab's), or the first page.
  func evaluate(_ expression: String, inPageTitled title: String?) async throws -> Any? {
    let session = try await attach { $0["title"] as? String == title }
    defer { session.close() }
    return try await session.evaluate(expression)
  }

  /// Evaluates `expression` in the first page whose URL starts with `prefix`.
  func evaluate(_ expression: String, inPageAt prefix: String) async throws -> Any? {
    let session = try await attach(fallingBack: false) { ($0["url"] as? String)?.hasPrefix(prefix) == true }
    defer { session.close() }
    return try await session.evaluate(expression)
  }

  /// A session on the page whose title is `title`, which keeps what it
  /// overrides until it's closed: DevTools drops a session's overrides as it
  /// detaches.
  func attach(toPageTitled title: String?) async throws -> Session {
    try await attach { $0["title"] as? String == title }
  }

  private func attach(fallingBack: Bool = true, where matches: ([String: Any]) -> Bool) async throws -> Session {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/json/list")!)
    let targets = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? [])
      .filter { $0["type"] as? String == "page" }
    guard let target = targets.first(where: matches) ?? (fallingBack ? targets.first : nil),
      let socketURL = (target["webSocketDebuggerUrl"] as? String).flatMap(URL.init(string:))
    else {
      throw DirectorError("no page to attach to")
    }
    return Session(url: socketURL)
  }

  final class Session {
    private let socket: URLSessionWebSocketTask
    private var lastID = 0

    fileprivate init(url: URL) {
      socket = URLSession.shared.webSocketTask(with: url)
      socket.resume()
    }

    /// Sends a command and waits for its result.
    @discardableResult
    func send(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
      lastID += 1
      let id = lastID
      let body = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
      try await socket.send(.string(String(decoding: body, as: UTF8.self)))
      while true {
        guard case .string(let text) = try await socket.receive(),
          let reply = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
          reply["id"] as? Int == id
        else {
          continue
        }
        if let error = reply["error"] as? [String: Any] {
          throw DirectorError("DevTools \(method): \(error["message"] ?? error)")
        }
        return reply["result"] as? [String: Any] ?? [:]
      }
    }

    func evaluate(_ expression: String) async throws -> Any? {
      let result = try await send(
        "Runtime.evaluate", ["expression": expression, "returnByValue": true, "awaitPromise": true])
      if let exception = result["exceptionDetails"] as? [String: Any] {
        let description = (exception["exception"] as? [String: Any])?["description"] ?? exception["text"] ?? ""
        throw DirectorError("the page threw: \(description)")
      }
      return (result["result"] as? [String: Any])?["value"]
    }

    func close() {
      socket.cancel(with: .normalClosure, reason: nil)
    }
  }
}
