import AppKit

/// The strip along the window's right edge that the page stops short of,
/// where TabPicker opens. It draws the page as the top of a stack (see
/// TabStackColors), reaching under the page to show around its corners.
final class PageGutter: NSView {
  /// How much of the window's width the gutter takes from the page.
  nonisolated static let width: CGFloat = 8
  /// How far the gutter reaches under the page: past its rounded corners.
  static let underlap: CGFloat = 32
  /// The page's corner radius, the window's. The slivers' match it.
  static let cornerRadius: CGFloat = 16

  private enum Metrics {
    /// How far each sliver's right edge is past the page's.
    static let nearReach: CGFloat = 3
    static let farReach: CGFloat = 5.5
    /// How far each is inset from the page's top and bottom, so it wraps
    /// around the page's rounded corners a step in from the one in front.
    static let nearInset: CGFloat = 5.5
    static let farInset: CGFloat = 11
    static let borderWidth: CGFloat = 0.5
  }

  /// The page's background color, which the stack's colors come from. It
  /// can be a dynamic color, which resolves in the gutter's appearance.
  var pageColor: NSColor = .white {
    didSet {
      if pageColor != oldValue {
        needsDisplay = true
      }
    }
  }

  // The edges of the pages behind this one; the far one is under the near.
  private let farSliver = CALayer()
  private let nearSliver = CALayer()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    for sliver in [farSliver, nearSliver] {
      sliver.cornerRadius = Self.cornerRadius
      sliver.cornerCurve = .continuous
      sliver.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
      sliver.borderWidth = Metrics.borderWidth
      layer?.addSublayer(sliver)
    }
    layoutSlivers()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    layoutSlivers()
  }

  /// Each sliver starts under the page, whose edge is `underlap` in.
  private func layoutSlivers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (sliver, reach, inset) in [
      (farSliver, Metrics.farReach, Metrics.farInset),
      (nearSliver, Metrics.nearReach, Metrics.nearInset),
    ] {
      sliver.frame = CGRect(
        x: 0, y: inset, width: Self.underlap + reach,
        height: max(bounds.height - 2 * inset, 0))
    }
    CATransaction.commit()
  }

  // MARK: Drawing

  override var wantsUpdateLayer: Bool { true }

  // Also called when the appearance changes, with it current.
  override func updateLayer() {
    let colors = TabStackColors(page: pageColor)
    let isDark =
      effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let border =
      isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.1)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.backgroundColor = colors.frame
    farSliver.backgroundColor = colors.far
    nearSliver.backgroundColor = colors.near
    for sliver in [farSliver, nearSliver] {
      sliver.borderColor = border.cgColor
    }
    CATransaction.commit()
  }

  // MARK: Scrolling

  /// Scrolls the page: passes the event to the page's view beside the
  /// pointer.
  override func scrollWheel(with event: NSEvent) {
    guard let root = window?.contentView else {
      return
    }
    // The page's last column. The content view's superview (the frame view)
    // has window coordinates.
    let edge = convert(NSPoint(x: Self.underlap - 1, y: 0), to: nil).x
    let target = root.hitTest(NSPoint(x: edge, y: event.locationInWindow.y))
    if let target, target !== self {
      target.scrollWheel(with: event)
    }
  }
}

/// The tab stack's colors for a page: near and far slivers stepping from the
/// page to a frame, a grey 50 away in apparent contrast (lighter behind a dark
/// page), with lightness mixed in sRGB and a hint of the page's hue.
struct TabStackColors {
  let near: CGColor
  let far: CGColor
  let frame: CGColor

  private enum Tone {
    /// How far the frame is from the page, in apparent contrast: every page
    /// gets the range a white page has down to a dark frame.
    static let frameDistance = 50.0
    /// Where each sliver's color is mixed between the page's (0) and the
    /// frame's (1).
    static let nearPosition = 0.32
    static let farPosition = 0.62
    /// The slivers' chroma (OKLab) in the page's hue, and how far that hue
    /// turns with each step back.
    static let tintChroma = 0.02
    static let hueTurn = 5 * Double.pi / 180
    /// Less chroma than this, and the page has no hue to pass on.
    static let minPageChroma = 0.004
  }

  init(page color: NSColor) {
    // A transparent page shows Chrome's white behind it.
    let srgb = color.usingColorSpace(.sRGB) ?? .white
    let alpha = Double(srgb.alphaComponent)
    let page =
      SIMD3(
        Double(srgb.redComponent), Double(srgb.greenComponent),
        Double(srgb.blueComponent)) * alpha + SIMD3(repeating: 1 - alpha)
    let lab = OKLab(page)
    let lighter = lab.lightness < 0.6
    let frame = OKLab.grey(
      apparentLightness: apparentLightness(page)
        + (lighter ? 1 : -1) * Tone.frameDistance)
    let hue: Double? =
      lab.chroma > Tone.minPageChroma ? atan2(lab.b, lab.a) : nil

    func sliver(at position: Double, step: Double) -> CGColor {
      let mixed = page + (frame - page) * position
      var tint = SIMD2<Double>.zero
      if let hue {
        let turned = hue + Tone.hueTurn * step
        tint = Tone.tintChroma * SIMD2(cos(turned), sin(turned))
      }
      return cgColor(
        OKLab.color(apparentLightness: apparentLightness(mixed), ab: tint))
    }
    near = sliver(at: Tone.nearPosition, step: 1)
    far = sliver(at: Tone.farPosition, step: 2)
    self.frame = cgColor(frame)
  }
}

// MARK: Color science

/// APCA's lightness for an sRGB color (components 0–1), with luminance raised
/// near black for flare off the display. Its differences track how different
/// colors look, which in the dark is much less than OKLab says.
private func apparentLightness(_ rgb: SIMD3<Double>) -> Double {
  let c = SIMD3(pow(rgb.x, 2.4), pow(rgb.y, 2.4), pow(rgb.z, 2.4))
  var y = 0.2126729 * c.x + 0.7151522 * c.y + 0.072175 * c.z
  if y < 0.022 {
    y += pow(0.022 - y, 1.414)
  }
  return 114 * pow(y, 0.56)
}

private func cgColor(_ rgb: SIMD3<Double>) -> CGColor {
  CGColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
}

/// A color in OKLab (Björn Ottosson's perceptual space).
private struct OKLab {
  var lightness: Double
  var a: Double
  var b: Double

  var chroma: Double { hypot(a, b) }

  init(lightness: Double, a: Double, b: Double) {
    self.lightness = lightness
    self.a = a
    self.b = b
  }

  /// From sRGB (components 0–1).
  init(_ rgb: SIMD3<Double>) {
    let r = Self.linear(rgb.x), g = Self.linear(rgb.y), b = Self.linear(rgb.z)
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    lightness = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
    self.b = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
  }

  /// In sRGB (components 0–1), clamped to it.
  var rgb: SIMD3<Double> {
    let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
    let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
    let s = pow(lightness - 0.0894841775 * a - 1.291485548 * b, 3)
    return SIMD3(
      Self.encoded(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
      Self.encoded(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
      Self.encoded(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s))
  }

  static func grey(apparentLightness target: Double) -> SIMD3<Double> {
    color(apparentLightness: target, ab: .zero)
  }

  /// The color with this hue and chroma (`ab`) and apparent lightness, as
  /// near as sRGB gets.
  static func color(apparentLightness target: Double, ab: SIMD2<Double>)
    -> SIMD3<Double>
  {
    let at = { (lightness: Double) in
      OKLab(lightness: lightness, a: ab.x, b: ab.y).rgb
    }
    var low = 0.0
    var high = 1.0
    for _ in 0..<26 {
      let mid = (low + high) / 2
      if apparentLightness(at(mid)) < target {
        low = mid
      } else {
        high = mid
      }
    }
    return at((low + high) / 2)
  }

  private static func linear(_ v: Double) -> Double {
    v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
  }

  private static func encoded(_ v: Double) -> Double {
    let v = min(max(v, 0), 1)
    return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
  }
}
