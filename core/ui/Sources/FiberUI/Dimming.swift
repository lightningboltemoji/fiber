import AppKit

/// How much black over the page darkens it: by about `drop` in CIE L* (0
/// black, 100 white), however light the page is. Black at a fixed opacity
/// darkens by a ratio, a lot on a white page and next to nothing on a dark one.
struct Dimming {
  /// How much darker the page gets, in L*.
  var drop: Double
  /// The most black there is, for a page too dark to lose all of `drop`.
  var maxOpacity: Double

  /// The opacity of black that takes `drop` off a page whose mean L* is
  /// `lightness`. Layers blend in encoded values, which black scales.
  func opacity(forPageLightness lightness: Double) -> Double {
    let encoded = Self.encodedValue(ofLightness: lightness)
    guard encoded > 0 else {
      return maxOpacity
    }
    let dimmed = Self.encodedValue(ofLightness: max(lightness - drop, 0))
    return min(max(1 - dimmed / encoded, 0), maxOpacity)
  }

  /// How light `image` looks: its pixels' mean L*, the middle counting most,
  /// as the panels and prompts are there.
  static func lightness(of image: CGImage) -> Double? {
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
        // From 1 in the middle to 0 in the corners.
        let dx = (Double(x) + 0.5) / Double(width) * 2 - 1
        let dy = (Double(y) + 0.5) / Double(height) * 2 - 1
        let weight = 1 - (dx * dx + dy * dy) / 2
        let luminance = Double(luminances[y * rowLength + x])
        total += weight * lightness(ofLuminance: luminance)
        totalWeight += weight
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

  /// The encoded value (sRGB's, which Display P3 shares) of a gray of L*
  /// `lightness`.
  private static func encodedValue(ofLightness lightness: Double) -> Double {
    let luminance =
      lightness > 8 ? pow((lightness + 16) / 116, 3) : lightness * 27 / 24389
    return luminance <= 0.0031308
      ? 12.92 * luminance : 1.055 * pow(luminance, 1 / 2.4) - 0.055
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
