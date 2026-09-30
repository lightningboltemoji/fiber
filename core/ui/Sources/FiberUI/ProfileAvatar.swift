import AppKit
import FiberBridge

@objc @implementation extension FiberProfileAvatars {
  @objc(pngForAvatarIndex:pixelSize:)
  class func png(forAvatarIndex avatarIndex: Int, pixelSize: Int) -> Data {
    ProfileAvatar(index: avatarIndex).png(pixelSize: pixelSize)
  }
}

/// Fiber's profile avatars, a symbol on a colored disc, by Chrome's numbering
/// for its own (profile_avatar_icon_util.h): 26 is the placeholder, 27 to 55
/// are what a profile can pick, and Chrome's old 0 to 25 draw as those.
struct ProfileAvatar {
  static let placeholderIndex = 26
  /// What a new profile can have, in the order it's offered.
  static let choices = Array(26...55)

  private static let placeholder = (
    symbol: "person.fill", color: NSColor.systemGray, label: "Person"
  )
  /// From 27 on.
  private static let pickable: [(symbol: String, color: NSColor, label: String)] = [
    ("cat.fill", .systemOrange, "Cat"),
    ("dog.fill", .systemBrown, "Dog"),
    ("hare.fill", .systemPink, "Rabbit"),
    ("tortoise.fill", .systemGreen, "Turtle"),
    ("bird.fill", .systemTeal, "Bird"),
    ("fish.fill", .systemBlue, "Fish"),
    ("ladybug.fill", .systemRed, "Ladybug"),
    ("pawprint.fill", .systemIndigo, "Paw Print"),
    ("leaf.fill", .systemMint, "Leaf"),
    ("tree.fill", .systemGreen, "Tree"),
    ("camera.macro", .systemPurple, "Flower"),
    ("sun.max.fill", .systemOrange, "Sun"),
    ("moon.fill", .systemIndigo, "Moon"),
    ("star.fill", .systemYellow, "Star"),
    ("bolt.fill", .systemPurple, "Lightning"),
    ("flame.fill", .systemRed, "Flame"),
    ("drop.fill", .systemCyan, "Drop"),
    ("snowflake", .systemTeal, "Snowflake"),
    ("heart.fill", .systemPink, "Heart"),
    ("music.note", .systemRed, "Music"),
    ("gamecontroller.fill", .systemPurple, "Game Controller"),
    ("paintpalette.fill", .systemOrange, "Palette"),
    ("book.fill", .systemBrown, "Book"),
    ("cup.and.saucer.fill", .systemBrown, "Coffee"),
    ("airplane", .systemBlue, "Airplane"),
    ("briefcase.fill", .systemGray, "Briefcase"),
    ("house.fill", .systemGreen, "House"),
    ("graduationcap.fill", .systemIndigo, "Graduation Cap"),
    ("globe.americas.fill", .systemBlue, "Globe"),
  ]
  static var symbolNames: [String] {
    [placeholder.symbol] + pickable.map(\.symbol)
  }

  /// The symbol's height, as a share of the disc's.
  private static let symbolScale: CGFloat = 0.44

  let index: Int
  let symbolName: String
  let color: NSColor
  let label: String

  init(index: Int) {
    self.index = index
    let first = Self.placeholderIndex + 1
    let entry =
      switch index {
      case first..<(first + Self.pickable.count):
        Self.pickable[index - first]
      case 0..<Self.placeholderIndex:
        Self.pickable[index % Self.pickable.count]
      default:
        Self.placeholder
      }
    symbolName = entry.symbol
    color = entry.color
    label = entry.label
  }

  /// `size` points square.
  func image(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      draw(in: rect)
      return true
    }
  }

  func png(pixelSize: Int) -> Data {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
      return Data()
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:]) ?? Data()
  }

  private func draw(in rect: NSRect) {
    let disc = NSBezierPath(ovalIn: rect)
    NSGradient(
      starting: color.blended(withFraction: 0.25, of: .white) ?? color,
      ending: color.blended(withFraction: 0.2, of: .black) ?? color
    )?.draw(in: disc, angle: -90)
    let configuration = NSImage.SymbolConfiguration(
      pointSize: rect.height * Self.symbolScale, weight: .semibold
    ).applying(.init(paletteColors: [.white]))
    guard
      let symbol = NSImage(
        systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else {
      return
    }
    symbol.draw(
      in: NSRect(
        x: rect.midX - symbol.size.width / 2,
        y: rect.midY - symbol.size.height / 2,
        width: symbol.size.width, height: symbol.size.height))
  }
}
