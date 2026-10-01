import AppKit

/// Plays the part of the profile's PinStore: the pins every non-Incognito
/// window shows, in order.
@MainActor
final class MockPins {
  struct Pin {
    let id: String
    var url: String
    var title: String
  }

  private(set) var pins: [Pin] = []
  /// Called after every change, for the windows to show it.
  var onChange: () -> Void = {}
  private var lastID = 0

  func pin(withID id: String) -> Pin? {
    pins.first { $0.id == id }
  }

  @discardableResult
  func add(url: String, title: String) -> String {
    lastID += 1
    let id = "pin-\(lastID)"
    pins.append(Pin(id: id, url: url, title: title))
    onChange()
    return id
  }

  func remove(_ id: String) {
    pins.removeAll { $0.id == id }
    onChange()
  }

  func move(_ id: String, to index: Int) {
    guard let from = pins.firstIndex(where: { $0.id == id }) else {
      return
    }
    let pin = pins.remove(at: from)
    pins.insert(pin, at: min(max(index, 0), pins.count))
    onChange()
  }

  func update(_ id: String, url: String, title: String) {
    guard let index = pins.firstIndex(where: { $0.id == id }) else {
      return
    }
    pins[index].url = url
    pins[index].title = title
    onChange()
  }
}

/// Made-up favicons: the site's initial on a color of its own.
@MainActor
enum MockFavicon {
  private static var cache: [String: NSImage] = [:]

  static func image(for url: String) -> NSImage? {
    guard let host = URL(string: url)?.host(), !host.isEmpty else {
      return nil
    }
    if let image = cache[host] {
      return image
    }
    let hash = host.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
    let hue = CGFloat(abs(hash % 360)) / 360
    let letter = String(host.prefix(1)).uppercased()
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) {
      rect in
      NSColor(hue: hue, saturation: 0.6, brightness: 0.85, alpha: 1).setFill()
      NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
      let text = NSAttributedString(
        string: letter,
        attributes: [
          .font: NSFont.systemFont(ofSize: 11, weight: .bold),
          .foregroundColor: NSColor.white,
        ])
      let size = text.size()
      text.draw(
        at: NSPoint(
          x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
      return true
    }
    cache[host] = image
    return image
  }
}
