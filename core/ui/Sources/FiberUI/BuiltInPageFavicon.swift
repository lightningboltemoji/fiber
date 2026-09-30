import AppKit
import FiberBridge

@objc @implementation extension FiberBuiltInPageFavicon {
  /// Fiber's UI tints these. The gray is for where Chrome draws one as it is,
  /// with the same contrast against light and dark backgrounds.
  private static let color = NSColor(white: 0.5, alpha: 1)

  class func png(forHost host: String, pixelSize: Int) -> Data {
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let side = CGFloat(pixelSize)
    let (image, size) = BuiltInPageIcon.glyph(forHost: host, side: side)
    let rect = NSRect(
      x: ((side - size.width) / 2).rounded(),
      y: ((side - size.height) / 2).rounded(), width: size.width,
      height: size.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: rect)
    color.set()
    rect.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
  }
}

/// The icon of each of the browser's built-in pages, by its chrome:// host.
enum BuiltInPageIcon {
  static let symbolNames = [
    "settings": "gearshape",
    "history": "clock",
    "downloads": "arrow.down.circle",
    "extensions": "puzzlepiece.extension",
    "bookmarks": "book",
    "password-manager": "key",
    "flags": "flask",
    "version": "info.circle",
  ]
  static let otherSymbolName = "wrench.and.screwdriver"
  /// Of a favicon's side, as the lists size their SF Symbols (13 points in 16).
  private static let symbolScale: CGFloat = 13 / 16

  /// The page's glyph, and its size to draw in a square `side` points wide:
  /// Fiber's mark for the New Tab page, and an SF Symbol for the rest.
  @MainActor
  static func glyph(forHost host: String, side: CGFloat) -> (NSImage, NSSize) {
    if host == "newtab" {
      let size = FiberMark.image.size
      let scale = side / max(size.width, size.height)
      return (
        FiberMark.image,
        NSSize(width: size.width * scale, height: size.height * scale)
      )
    }
    let symbol = NSImage(
      systemSymbolName: symbolNames[host] ?? otherSymbolName,
      accessibilityDescription: nil
    )!.withSymbolConfiguration(
      .init(pointSize: side * symbolScale, weight: .regular))!
    return (symbol, symbol.size)
  }
}
