import AppKit

/// Plays the part of the profile's PinStore: the pins and shelves every
/// non-Incognito window shows, in order. Shelves' pages are pins with a shelf.
@MainActor
final class MockPins {
  struct Pin {
    let id: String
    var url: String
    var title: String
    /// Nil for one of the pins themselves.
    var shelfID: String?
  }

  struct Shelf {
    let id: String
    var name: String
  }

  /// The pins, then each shelf's pages in the shelves' order.
  private(set) var pins: [Pin] = []
  private(set) var shelves: [Shelf] = []
  /// Called after every change, for the windows to show it.
  var onChange: () -> Void = {}
  private var lastID = 0

  /// An ID for a pin about to be added, for its tab to be its pin's before
  /// the windows hear of it.
  func makeID() -> String {
    lastID += 1
    return "pin-\(lastID)"
  }

  func pin(withID id: String) -> Pin? {
    pins.first { $0.id == id }
  }

  /// The pins, or a shelf's pages.
  func pins(on shelfID: String?) -> [Pin] {
    pins.filter { $0.shelfID == shelfID }
  }

  @discardableResult
  func add(
    url: String, title: String, shelfID: String? = nil, id: String? = nil
  ) -> String {
    let id = id ?? makeID()
    pins.append(Pin(id: id, url: url, title: title, shelfID: shelfID))
    changed()
    return id
  }

  func remove(_ id: String) {
    pins.removeAll { $0.id == id }
    changed()
  }

  /// Moves the pin to `index` among those on its shelf (or not on one).
  func move(_ id: String, to index: Int) {
    guard let pin = pin(withID: id) else {
      return
    }
    var siblings = pins(on: pin.shelfID)
    siblings.removeAll { $0.id == id }
    siblings.insert(pin, at: min(max(index, 0), siblings.count))
    pins = pins.filter { $0.shelfID != pin.shelfID } + siblings
    changed()
  }

  /// Moves the pin to the end of the shelf, or of the pins for nil.
  func moveToShelf(_ id: String, _ shelfID: String?) {
    guard let index = pins.firstIndex(where: { $0.id == id }) else {
      return
    }
    var pin = pins.remove(at: index)
    pin.shelfID = shelfID
    pins.append(pin)
    changed()
  }

  func update(_ id: String, url: String, title: String) {
    guard let index = pins.firstIndex(where: { $0.id == id }) else {
      return
    }
    pins[index].url = url
    pins[index].title = title
    changed()
  }

  @discardableResult
  func addShelf(named name: String, pages: [(url: String, title: String)] = [])
    -> String
  {
    lastID += 1
    let id = "shelf-\(lastID)"
    shelves.append(Shelf(id: id, name: name))
    for page in pages {
      pins.append(
        Pin(id: makeID(), url: page.url, title: page.title, shelfID: id))
    }
    changed()
    return id
  }

  func renameShelf(_ id: String, to name: String) {
    guard let index = shelves.firstIndex(where: { $0.id == id }) else {
      return
    }
    shelves[index].name = name
    changed()
  }

  /// Removes the shelf and its pages.
  func removeShelf(_ id: String) {
    shelves.removeAll { $0.id == id }
    pins.removeAll { $0.shelfID == id }
    changed()
  }

  /// `count` made-up shelves, the first few with pages.
  func addSampleShelves(_ count: Int) {
    for sample in Self.samples.prefix(count) {
      addShelf(
        named: sample.name,
        pages: sample.pages.map { ("https://\($0.0)", $0.1) })
    }
  }

  /// Keeps the store's order, as PinStore does, and tells the windows.
  private func changed() {
    let order = [nil] + shelves.map { Optional($0.id) }
    pins = order.flatMap { shelfID in pins.filter { $0.shelfID == shelfID } }
    onChange()
  }

  private static let samples: [(name: String, pages: [(String, String)])] = [
    (
      "Later",
      [
        ("video.example/watch?v=glass", "Designing with Liquid Glass — Video"),
        ("longreads.example/the-quiet-web", "The Quiet Web — Longreads"),
        (
          "papers.example/abs/2609.01234v3",
          "Sparse Retrieval at Scale — Papers"
        ),
        ("podcast.example/ep/218", "Ep. 218: Browsers All the Way Down"),
        ("blog.example/posts/in-defense-of-tabs", "In Defense of Tab Hoarding"),
      ]
    ),
    (
      "Research",
      [
        ("wiki.example/Liquid_glass", "Liquid glass — Wiki"),
        ("docs.example/spec/spaces", "Spaces — Design spec"),
        ("forum.example/t/arc-spaces-retrospective/912", "Arc spaces, a retrospective"),
        ("code.example/chromium/tab_strip_model.h", "tab_strip_model.h — Code"),
      ]
    ),
    (
      "Recipes",
      [
        ("recipes.example/ramen", "Shoyu Ramen — Recipes"),
        ("recipes.example/focaccia", "Overnight Focaccia — Recipes"),
        ("video.example/watch?v=knife-skills", "Knife Skills 101 — Video"),
      ]
    ),
    (
      "Trip to Lisbon",
      [
        ("travel.example/flights/sfo-lis", "SFO → LIS — Flights"),
        ("maps.example/lisbon/alfama", "Alfama, Lisbon — Maps"),
      ]
    ),
    ("Gift Ideas", [("shop.example/p/ceramic-mug", "Ceramic Mug — Shop")]),
    (
      "Reading",
      [
        "The Quiet Web", "Against Infinite Scroll", "A Field Guide to Fonts",
        "How Glass Is Made", "The Last Bookbinder", "Notes on Rebasing",
        "Why Maps Lie", "The Long Tail of Tabs", "On Keyboards",
        "Small Tools", "The Weight of Pixels", "Slow Software",
        "Learning to Draw at 40", "Ferments", "The Case for Paper",
        "Night Trains of Europe", "What Sync Costs", "Desk Plants, Ranked",
        "A History of the Cursor", "Leaving Things Unfinished",
      ].map { title in
        let slug = title.lowercased().split(separator: " ").joined(
          separator: "-")
        return ("longreads.example/\(slug)", "\(title) — Longreads")
      }
    ),
    ("Fiber", [("code.example/fiber/pulls", "Pull requests — Code")]),
    ("Taxes 2026", []),
    ("Inspiration", []),
    ("Music", [("music.example/playlist/focus", "Focus — Music")]),
  ]
}

/// Made-up favicons: the site's initial on a color of its own.
@MainActor
enum MockFavicon {
  private static var cache: [String: NSImage] = [:]

  static func image(for url: String) -> NSImage? {
    guard let host = URL(string: url)?.host(), !host.isEmpty else {
      return nil
    }
    if let favicon = DemoSites.favicon(for: url) {
      return favicon
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
