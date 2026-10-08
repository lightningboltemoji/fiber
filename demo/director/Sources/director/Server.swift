import Foundation
import Network
import Security

/// Serves demo/sites on localhost, over HTTP and HTTPS, a folder per host
/// (`sites/wayfarer.travel/lisbon/index.html` for
/// `https://wayfarer.travel/lisbon/`). Fiber reaches it for every host through
/// `--host-resolver-rules`, so the take never touches the network.
final class SiteServer: @unchecked Sendable {
  private let root: URL
  private let queue = DispatchQueue(label: "sites")
  private var listeners: [NWListener] = []
  /// Every `host/path` asked for, guarded by `queue`.
  private var requested = Set<String>()

  init(root: URL) {
    self.root = root
  }

  /// The flags that send Fiber's requests here, trusting its certificate.
  func start(certificateIn folder: URL) async throws -> [String] {
    let (identity, spki) = try Self.makeIdentity(in: folder)
    let tls = NWProtocolTLS.Options()
    sec_protocol_options_set_local_identity(tls.securityProtocolOptions, sec_identity_create(identity)!)
    let http = try await listen(NWParameters(tls: nil))
    let https = try await listen(NWParameters(tls: tls))
    return [
      "--host-resolver-rules=MAP *:80 127.0.0.1:\(http), MAP *:443 127.0.0.1:\(https)",
      "--ignore-certificate-errors-spki-list=\(spki)",
    ]
  }

  /// A self-signed certificate for every host, which Chrome trusts by its
  /// public key's hash (`--ignore-certificate-errors-spki-list`), as Chrome's
  /// own Web Page Replay does.
  private static func makeIdentity(in folder: URL) throws -> (SecIdentity, String) {
    let script = """
      set -e
      /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 30 \\
        -subj '/CN=Fiber demo' 2>/dev/null
      /usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out identity.p12 -passout pass:demo
      /usr/bin/openssl x509 -in cert.pem -pubkey -noout | /usr/bin/openssl pkey -pubin -outform der \\
        | /usr/bin/openssl dgst -sha256 -binary | /usr/bin/openssl base64
      """
    let shell = Process()
    shell.executableURL = URL(filePath: "/bin/sh")
    shell.arguments = ["-c", script]
    shell.currentDirectoryURL = folder
    let output = Pipe()
    shell.standardOutput = output
    try shell.run()
    shell.waitUntilExit()
    let spki = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    var items: CFArray?
    let status = SecPKCS12Import(
      try Data(contentsOf: folder.appending(path: "identity.p12")) as CFData,
      [kSecImportExportPassphrase: "demo", kSecImportToMemoryOnly: true] as CFDictionary, &items)
    guard shell.terminationStatus == 0, status == errSecSuccess,
      let item = (items as? [[String: Any]])?.first, let identity = item[kSecImportItemIdentity as String]
    else {
      throw DirectorError("couldn't make the sites' certificate (\(status))")
    }
    return (identity as! SecIdentity, spki)
  }

  private func listen(_ parameters: NWParameters) async throws -> UInt16 {
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    listeners.append(listener)
    listener.newConnectionHandler = { [weak self] connection in
      self?.serve(connection)
    }
    return try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          listener.stateUpdateHandler = nil
          continuation.resume(returning: listener.port!.rawValue)
        case .failed(let error):
          listener.stateUpdateHandler = nil
          continuation.resume(throwing: error)
        default:
          break
        }
      }
      listener.start(queue: queue)
    }
  }

  func stop() {
    listeners.forEach { $0.cancel() }
  }

  func hasServed(_ url: URL) -> Bool {
    let key = (url.host() ?? "") + (url.path().isEmpty ? "/" : url.path())
    return queue.sync { requested.contains(key) }
  }

  private func serve(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(connection, buffer: Data())
  }

  private func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, done, error in
      var buffer = buffer
      if let data {
        buffer.append(data)
      }
      if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
        let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
        respond(to: head, on: connection)
      } else if done || error != nil {
        connection.cancel()
      } else {
        receive(connection, buffer: buffer)
      }
    }
  }

  private func respond(to head: String, on connection: NWConnection) {
    let lines = head.components(separatedBy: "\r\n")
    let request = lines.first?.split(separator: " ") ?? []
    let host = lines.dropFirst()
      .first { $0.lowercased().hasPrefix("host:") }
      .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces).split(separator: ":").first.map(String.init) ?? "" }
      ?? ""
    guard request.count >= 2, request[0] == "GET" || request[0] == "HEAD" else {
      return send(status: "405 Method Not Allowed", body: Data(), type: "text/plain", on: connection)
    }
    let rawPath = String(request[1].split(separator: "?").first ?? "/")
    let path = rawPath.removingPercentEncoding ?? rawPath
    requested.insert(host + path)

    let site = root.appending(path: host, directoryHint: .isDirectory)
    var file = site.appending(path: path)
    var isDirectory: ObjCBool = false
    guard !host.isEmpty, !path.contains(".."),
      FileManager.default.fileExists(atPath: file.path(), isDirectory: &isDirectory)
    else {
      return send(status: "404 Not Found", body: Data("Not found".utf8), type: "text/plain", on: connection)
    }
    if isDirectory.boolValue {
      guard path.hasSuffix("/") else {
        return send(status: "301 Moved Permanently", body: Data(), type: "text/plain",
          extra: "Location: \(path)/\r\n", on: connection)
      }
      file = file.appending(path: "index.html")
    }
    guard let body = try? Data(contentsOf: file) else {
      return send(status: "404 Not Found", body: Data("Not found".utf8), type: "text/plain", on: connection)
    }
    send(status: "200 OK", body: request[0] == "HEAD" ? Data() : body, type: Self.type(of: file), on: connection)
  }

  private func send(status: String, body: Data, type: String, extra: String = "", on connection: NWConnection) {
    let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
      + "Cache-Control: no-store\r\nConnection: close\r\n\(extra)\r\n"
    connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
  }

  private static func type(of file: URL) -> String {
    switch file.pathExtension.lowercased() {
    case "html": "text/html; charset=utf-8"
    case "css": "text/css; charset=utf-8"
    case "js", "mjs": "text/javascript; charset=utf-8"
    case "json": "application/json"
    case "svg": "image/svg+xml"
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "webp": "image/webp"
    case "ico": "image/x-icon"
    case "woff2": "font/woff2"
    case "mp4": "video/mp4"
    default: "application/octet-stream"
    }
  }
}
