import AppKit
import Testing

@testable import FiberUI

struct DimmingTests {
  private let dimming = Dimming(light: 0.6, dark: 0.7)

  @Test func darkensDarkerPagesMore() {
    #expect(abs(dimming.opacity(forPageLightness: 100) - 0.6) < 1e-9)
    #expect(abs(dimming.opacity(forPageLightness: 50) - 0.65) < 1e-9)
    #expect(abs(dimming.opacity(forPageLightness: 0) - 0.7) < 1e-9)
  }

  @Test func staysBetweenItsOpacities() {
    #expect(abs(dimming.opacity(forPageLightness: 120) - 0.6) < 1e-9)
    #expect(abs(dimming.opacity(forPageLightness: -5) - 0.7) < 1e-9)
  }

  @Test func measuresAnImagesLightness() throws {
    #expect(try abs(#require(Self.lightness(ofGray: 1)) - 100) < 0.5)
    #expect(try abs(#require(Self.lightness(ofGray: 0))) < 0.5)
    #expect(try abs(#require(Self.lightness(ofGray: 0x80 / 255)) - 53.6) < 0.5)
  }

  @Test func countsTheMiddleMost() throws {
    // White in the middle, black around it.
    let image = try #require(
      Self.image(width: 8, height: 8) { x, y in
        (2..<6).contains(x) && (2..<6).contains(y) ? 1 : 0
      })
    let lightness = try #require(Dimming.lightness(of: image))
    // A quarter of the pixels, but more than a quarter of the weight.
    #expect(lightness > 25)
  }

  /// The lightness Dimming measures in an sRGB image of one gray.
  private static func lightness(ofGray gray: Double) -> Double? {
    image(width: 4, height: 4) { _, _ in gray }.flatMap(Dimming.lightness(of:))
  }

  private static func image(
    width: Int, height: Int, gray: (Int, Int) -> Double
  ) -> CGImage? {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    for y in 0..<height {
      for x in 0..<width {
        let value = gray(x, y)
        context?.setFillColor(red: value, green: value, blue: value, alpha: 1)
        context?.fill(CGRect(x: x, y: y, width: 1, height: 1))
      }
    }
    return context?.makeImage()
  }
}
