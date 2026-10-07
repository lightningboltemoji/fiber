import AppKit
import SwiftUI

/// The opacity of black over a page, by how light the page is (its CIE L*, 0
/// black to 100 white). Black takes away a share of the page's light, so a
/// dark page, with less to lose, takes more to look as dimmed.
struct Dimming {
  /// Over a white page, and over a black one.
  var light: Double
  var dark: Double

  /// Between `dark` and `light`, in step with `lightness`.
  func opacity(forPageLightness lightness: Double) -> Double {
    dark + (light - dark) * min(max(lightness / 100, 0), 1)
  }

  /// How light `image` looks: its pixels' mean L*, the middle counting most,
  /// as the tab overlay is there.
  static func lightness(of image: CGImage) -> Double? {
    meanLightness(of: image) { dx, dy in 1 - (dx * dx + dy * dy) / 2 }
  }

  /// How light the part of `image` in `region` looks: its pixels' mean L*.
  /// `region` is in units of the image's size, from its top-left corner.
  static func lightness(of image: CGImage, in region: CGRect) -> Double? {
    let size = CGSize(width: image.width, height: image.height)
    let pixels = CGRect(
      x: region.minX * size.width, y: region.minY * size.height,
      width: region.width * size.width, height: region.height * size.height
    ).integral.intersection(CGRect(origin: .zero, size: size))
    guard !pixels.isEmpty, let part = image.cropping(to: pixels) else {
      return nil
    }
    return meanLightness(of: part) { _, _ in 1 }
  }

  /// `image`'s pixels' mean L*, each weighted by `weight` of where it is,
  /// from -1 to 1 across and down.
  private static func meanLightness(
    of image: CGImage, weight: (Double, Double) -> Double
  ) -> Double? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 32,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.linearGray)!,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
          | CGBitmapInfo.floatComponents.rawValue
          | CGImageByteOrderInfo.order32Host.rawValue)
    else {
      return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else {
      return nil
    }
    let rowLength = context.bytesPerRow / MemoryLayout<Float>.stride
    let luminances = data.bindMemory(
      to: Float.self, capacity: rowLength * height)
    var total = 0.0
    var totalWeight = 0.0
    for y in 0..<height {
      for x in 0..<width {
        let pixelWeight = weight(
          (Double(x) + 0.5) / Double(width) * 2 - 1,
          (Double(y) + 0.5) / Double(height) * 2 - 1)
        let luminance = Double(luminances[y * rowLength + x])
        total += pixelWeight * lightness(ofLuminance: luminance)
        totalWeight += pixelWeight
      }
    }
    return total / totalWeight
  }

  /// How light `color` is, in L*. A dynamic color is resolved in the current
  /// drawing appearance.
  static func lightness(of color: NSColor) -> Double? {
    guard
      let gray = color.cgColor.converted(
        to: CGColorSpace(name: CGColorSpace.linearGray)!,
        intent: .defaultIntent, options: nil),
      let luminance = gray.components?.first
    else {
      return nil
    }
    return lightness(ofLuminance: Double(luminance))
  }

  private static func lightness(ofLuminance luminance: Double) -> Double {
    luminance > 216 / 24389
      ? 116 * cbrt(luminance) - 16 : luminance * 24389 / 27
  }
}

/// Black over the window. It's only drawn: clicks go to whatever is over it,
/// or nowhere.
class DimView: NSView {
  /// The black, in a layer of its own: AppKit keeps the view's own layer's
  /// opacity in step with its alphaValue.
  private let tint = CALayer()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    tint.backgroundColor = NSColor.black.cgColor
    tint.opacity = 0
    layer?.addSublayer(tint)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Takes the black to `opacity` over `duration`, from wherever it is now,
  /// even partway through an animation.
  func setOpacity(
    _ opacity: Float, duration: TimeInterval,
    timing: CAMediaTimingFunctionName = .easeInEaseOut
  ) {
    let fromOpacity = (tint.presentation() ?? tint).opacity
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    tint.opacity = opacity
    if duration > 0 {
      let animation = CABasicAnimation(keyPath: "opacity")
      animation.fromValue = fromOpacity
      animation.toValue = opacity
      animation.duration = duration
      animation.timingFunction = CAMediaTimingFunction(name: timing)
      tint.add(animation, forKey: "opacity")
    } else {
      tint.removeAnimation(forKey: "opacity")
    }
    CATransaction.commit()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    tint.frame = bounds
    CATransaction.commit()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

/// Black pooled under glass, over the dimming across the window: each shape
/// grown by `spread`, the shapes merged, then blurred by `radius`, so it's
/// darkest under the glass and fades out past it.
struct DimmingPool: View {
  struct Shape: Identifiable {
    let id: String
    let frame: CGRect
    let cornerRadius: CGFloat
  }

  let shapes: [Shape]
  let spread: CGFloat
  let radius: CGFloat
  let opacity: Double

  var body: some View {
    // Only as large as the blur reaches, which it costs to draw, and in an
    // overlay, so that reaching past the container doesn't resize it.
    let margin = spread + 3 * radius
    let bounds = shapes.reduce(CGRect.null) { $0.union($1.frame) }
      .insetBy(dx: -margin, dy: -margin)
    Color.clear.overlay(alignment: .topLeading) {
      if !bounds.isNull {
        pool(in: bounds)
      }
    }
  }

  private func pool(in bounds: CGRect) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(shapes) { shape in
        RoundedRectangle(
          cornerRadius: shape.cornerRadius + spread, style: .continuous
        )
        .fill(.black)
        .frame(
          width: shape.frame.width + 2 * spread,
          height: shape.frame.height + 2 * spread
        )
        .offset(
          x: shape.frame.minX - spread - bounds.minX,
          y: shape.frame.minY - spread - bounds.minY)
      }
    }
    .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
    // Where shapes overlap, they're black once.
    .compositingGroup()
    .blur(radius: radius)
    .opacity(opacity)
    .offset(x: bounds.minX, y: bounds.minY)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
