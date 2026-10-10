import AppKit
import WebKit

/// The demo video's made-up sites (demo/sites) in place of the harness's
/// own, with their titles and icons, each page drawn once by WebKit for mock
/// pages to show. On with `--demo-sites`.
@MainActor
enum DemoSites {
  static let isEnabled = CommandLine.arguments.contains("--demo-sites")
  static let didRender = Notification.Name("DemoSitesDidRender")

  /// In an order a trip's planning might leave them.
  static let urls = [
    "https://margin.so/", "https://wayfarer.travel/lisbon/",
    "https://casa-alecrim.pt/", "https://wayfarer.travel/lisbon/coffee/",
    "https://saltwater.kitchen/pasteis-de-nata/", "https://lettera.app/",
    "https://daybook.app/", "https://meridian.news/night-trains/",
    "https://caldera.dev/docs/getting-started/", "https://kestrel.so/search/",
    "https://hum.fm/", "https://meridian.news/", "https://caldera.dev/",
    "https://lumen.camera/", "https://saltwater.kitchen/",
    "https://wayfarer.travel/", "https://kestrel.so/",
  ]

  private static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appending(path: "demo/sites")

  private static var titles: [String: String] = [:]
  private static var favicons: [String: NSImage] = [:]
  private static var images: [String: NSImage] = [:]
  private static var renderers: [Renderer] = []

  static func title(for url: String) -> String? {
    guard let file = file(for: url) else {
      return nil
    }
    if let title = titles[url] {
      return title
    }
    let html = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    let title = html.firstMatch(of: #/<title>(.*?)</title>/#).map {
      String($0.1)
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&ndash;", with: "–")
        .replacingOccurrences(of: "&mdash;", with: "—")
    }
    titles[url] = title
    return title
  }

  static func favicon(for url: String) -> NSImage? {
    guard isEnabled, let host = URL(string: url)?.host() else {
      return nil
    }
    if let image = favicons[host] {
      return image
    }
    let image = NSImage(
      contentsOf: root.appending(path: host).appending(path: "favicon.svg"))
    image?.size = NSSize(width: 16, height: 16)
    favicons[host] = image
    return image
  }

  /// The page at `url` as WebKit drew it, once it has.
  static func image(for url: String) -> NSImage? {
    images[url]
  }

  /// Draws every page at `size`, then posts didRender.
  static func render(at size: NSSize, completion: @escaping () -> Void) {
    var remaining = urls.count
    for url in urls {
      guard let file = file(for: url) else {
        remaining -= 1
        continue
      }
      let renderer = Renderer(size: size)
      renderers.append(renderer)
      renderer.render(file, readAccess: root) { image in
        images[url] = image
        remaining -= 1
        if remaining == 0 {
          renderers = []
          NotificationCenter.default.post(name: didRender, object: nil)
          completion()
        }
      }
    }
  }

  private static func file(for url: String) -> URL? {
    guard isEnabled, let parsed = URL(string: url), let host = parsed.host()
    else {
      return nil
    }
    let file = root.appending(path: host).appending(path: parsed.path())
      .appending(path: "index.html")
    return FileManager.default.fileExists(atPath: file.path) ? file : nil
  }

  private final class Renderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var completion: (NSImage?) -> Void = { _ in }

    init(size: NSSize) {
      webView = WKWebView(frame: NSRect(origin: .zero, size: size))
      super.init()
      webView.navigationDelegate = self
    }

    func render(
      _ file: URL, readAccess: URL, completion: @escaping (NSImage?) -> Void
    ) {
      self.completion = completion
      webView.loadFileURL(file, allowingReadAccessTo: readAccess)
    }

    nonisolated func webView(
      _ webView: WKWebView, didFinish navigation: WKNavigation!
    ) {
      MainActor.assumeIsolated {
        // A moment for fonts and layout to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          MainActor.assumeIsolated {
            self.webView.takeSnapshot(with: nil) { image, _ in
              MainActor.assumeIsolated { self.completion(image) }
            }
          }
        }
      }
    }

    nonisolated func webView(
      _ webView: WKWebView, didFail navigation: WKNavigation!,
      withError error: any Error
    ) {
      MainActor.assumeIsolated { completion(nil) }
    }
  }
}
