import AppKit
import FiberBridge
import SwiftUI

/// The layout of the pins in rows as wide as the tab overlay's panel, the
/// first just above it. Points are from the grid's bottom-left corner, y
/// growing down as in the overlay, so the circles are at negative y.
enum PinGridLayout {
  static let diameter: CGFloat = 36
  /// Between circles, across and up, and from the first row to the panel.
  static let spacing: CGFloat = GlassCapsule.spacing
  /// How long a pin takes to pop out (see pinPop).
  static let popOutDuration: TimeInterval = 0.2
  private static let step = diameter + spacing

  static func columns(width: CGFloat) -> Int {
    max(Int((width + spacing) / step), 1)
  }

  /// The top-left corner of the circle at `index`.
  static func origin(of index: Int, width: CGFloat) -> CGPoint {
    let columns = columns(width: width)
    return CGPoint(
      x: CGFloat(index % columns) * step,
      y: -CGFloat(index / columns) * step - diameter)
  }

  static func height(count: Int, width: CGFloat) -> CGFloat {
    guard count > 0 else {
      return 0
    }
    let rows = (count - 1) / columns(width: width) + 1
    return CGFloat(rows) * step - spacing
  }

  /// The circle `point` is on, if any.
  static func index(at point: CGPoint, count: Int, width: CGFloat) -> Int? {
    (0..<count).first { index in
      let origin = origin(of: index, width: width)
      return hypot(
        point.x - origin.x - diameter / 2, point.y - origin.y - diameter / 2)
        <= diameter / 2
    }
  }

  /// Whether `point` is on a circle or in the gaps between them, rather than
  /// past the last one.
  static func covers(_ point: CGPoint, count: Int, width: CGFloat) -> Bool {
    let columns = columns(width: width)
    let column = Int(((point.x + spacing / 2) / step).rounded(.down))
    let row = Int(((spacing / 2 - point.y) / step).rounded(.down))
    return (0..<columns).contains(column) && row >= 0
      && row * columns + column < count
  }

  /// The place nearest `center`, for a circle dragged there.
  static func nearestIndex(to center: CGPoint, count: Int, width: CGFloat)
    -> Int
  {
    let columns = columns(width: width)
    let rows = (max(count, 1) - 1) / columns + 1
    let column = min(
      max(Int(((center.x - diameter / 2) / step).rounded()), 0), columns - 1)
    let row = min(
      max(Int(((-center.y - diameter / 2) / step).rounded()), 0), rows - 1)
    return min(row * columns + column, max(count - 1, 0))
  }
}

/// A pin being dragged to a new place.
struct PinDrag: Equatable {
  let pinID: String
  /// How far the pointer has moved it from its place.
  var offset: CGSize
  /// Where it would go if dropped now.
  var targetIndex: Int
}

/// The flourish around a pin as it's pinned or unpinned (see PinBurstView).
struct PinBurst: Identifiable {
  let id = UUID()
  let origin: CGPoint
  /// Its icon's color, if it has one.
  let color: NSColor?
}

/// Draws the pins; TabOverlay handles their input. While one's dragged, the
/// rest make room where it would go.
struct PinGrid: View {
  let model: TabOverlayModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let width = model.gridWidth
    let shown = model.shownPins
    ZStack(alignment: .bottomLeading) {
      // Holds the grid's bottom-left corner, which the rows rise from.
      Color.clear.frame(width: width, height: 0)

      ForEach(model.pins, id: \.pinID) { pin in
        let isDragged = model.pinDrag?.pinID == pin.pinID
        let index = model.pins.firstIndex { $0.pinID == pin.pinID } ?? 0
        let slot = shown.firstIndex { $0.pinID == pin.pinID } ?? index
        PinCircle(
          pin: pin, isActive: pin.tabID != 0 && pin.tabID == model.activeTabID,
          isSelected: model.selection == .pin(pin.pinID) && model.pinDrag == nil
        )
        // A dragged pin follows the pointer from its place.
        .offset(isDragged ? model.pinDrag?.offset ?? .zero : .zero)
        .place(
          at: PinGridLayout.origin(of: isDragged ? index : slot, width: width)
        )
        .zIndex(isDragged ? 1 : 0)
        // Others glide to make room; a dropped pin settles into its place.
        .animation(
          .spring(duration: 0.3, bounce: 0.15), value: isDragged ? -1 : slot)
        .transition(reduceMotion ? .opacity : .pinPop)
        .accessibilityElement()
        .accessibilityLabel(pin.title.isEmpty ? pin.url : pin.title)
        .accessibilityAddTraits(
          pin.tabID != 0 && pin.tabID == model.activeTabID
            ? [.isButton, .isSelected] : .isButton
        )
        .accessibilityAction { model.onOpenPin(pin.pinID) }
        .accessibilityAction(named: "Close Tab") {
          if pin.tabID != 0 {
            model.onClose(pin.tabID)
          }
        }
        .accessibilityAction(named: "Unpin") { model.onUnpin(pin.pinID) }
      }

      if !reduceMotion {
        ForEach(model.pinBursts) { burst in
          PinBurstView(color: burst.color).place(at: burst.origin)
        }
      }
    }
    .animation(.spring(duration: 0.3, bounce: 0), value: model.pins.map(\.pinID))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Pinned")
  }
}

extension View {
  /// Lays the view out with its top-left corner at `origin` from the
  /// bottom-left corner of a bottom-leading ZStack, so its own effects (a
  /// transition's scale) center on it.
  fileprivate func place(at origin: CGPoint) -> some View {
    alignmentGuide(.leading) { _ in -origin.x }
      .alignmentGuide(.bottom) { _ in -origin.y }
  }
}

extension AnyTransition {
  /// A pin pops in, zooming up from small and past its size before it
  /// settles, and pops out, swelling as it fades.
  fileprivate static var pinPop: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: PinPop(scale: 0.3, opacity: 0, blur: 6),
        identity: PinPop(scale: 1, opacity: 1, blur: 0)
      ).animation(.spring(duration: 0.5, bounce: 0.5)),
      removal: .modifier(
        active: PinPop(scale: 1.4, opacity: 0, blur: 3),
        identity: PinPop(scale: 1, opacity: 1, blur: 0)
      ).animation(.easeOut(duration: PinGridLayout.popOutDuration)))
  }
}

private struct PinPop: ViewModifier {
  let scale: CGFloat
  let opacity: Double
  let blur: CGFloat

  func body(content: Content) -> some View {
    content.scaleEffect(scale).opacity(opacity).blur(radius: blur)
  }
}

/// The flourish as a pin pops in or out: a ring swelling from it, and sparks
/// flying off it that fade as they go, in its icon's color.
struct PinBurstView: View {
  static let duration: TimeInterval = 0.6
  private static let sparkCount = 10

  let color: NSColor?
  @State private var travel: CGFloat = 0
  @State private var fade: Double = 0

  var body: some View {
    let tint = color.map { Color(nsColor: $0) } ?? Color.primary
    let radius = PinGridLayout.diameter / 2
    ZStack {
      Circle()
        .strokeBorder(tint.opacity(0.6), lineWidth: 1.5)
        .scaleEffect(1 + 0.4 * travel)
        .opacity(1 - travel)
      ForEach(0..<Self.sparkCount, id: \.self) { index in
        let spark = Double(index)
        // Unevenly spaced, and flying unevenly far.
        let angle =
          (spark + 0.35 * sin(spark * 12.9898)) / Double(Self.sparkCount) * 2
          * .pi
        let distance = radius + 3 + (10 + 8 * abs(sin(spark * 78.233))) * travel
        Circle()
          .fill(tint)
          .frame(width: 3.5, height: 3.5)
          .scaleEffect(1 - 0.6 * travel)
          .offset(x: cos(angle) * distance, y: sin(angle) * distance)
          .opacity(1 - fade)
      }
    }
    .frame(width: PinGridLayout.diameter, height: PinGridLayout.diameter)
    .allowsHitTesting(false)
    .onAppear {
      withAnimation(.easeOut(duration: Self.duration)) { travel = 1 }
      withAnimation(.easeIn(duration: Self.duration)) { fade = 1 }
    }
  }
}

extension NSImage {
  /// The color of its colored pixels, bright enough to show on glass, or nil
  /// for a gray or template image.
  var burstColor: NSColor? {
    guard !isTemplate,
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else {
      return nil
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(in: NSRect(x: 0, y: 0, width: 8, height: 8))
    NSGraphicsContext.restoreGraphicsState()
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var weight: CGFloat = 0
    for x in 0..<8 {
      for y in 0..<8 {
        guard let pixel = bitmap.colorAt(x: x, y: y) else {
          continue
        }
        // Each pixel counts as much as it shows.
        let alpha = pixel.alphaComponent
        red += pixel.redComponent * alpha
        green += pixel.greenComponent * alpha
        blue += pixel.blueComponent * alpha
        weight += alpha
      }
    }
    guard weight > 0 else {
      return nil
    }
    let average = NSColor(
      deviceRed: red / weight, green: green / weight, blue: blue / weight,
      alpha: 1)
    guard average.saturationComponent >= 0.15 else {
      return nil
    }
    return NSColor(
      deviceHue: average.hueComponent,
      saturation: average.saturationComponent,
      brightness: max(average.brightnessComponent, 0.7), alpha: 1)
  }
}

/// A pin: its page's icon in a circle of glass, ringed while its tab is the
/// active one, and dimmed while it isn't open in the window.
private struct PinCircle: View {
  private static let closedIconOpacity = 0.5

  let pin: FiberPinState
  let isActive: Bool
  let isSelected: Bool

  var body: some View {
    let rim = GlassCapsule.rimWidth
    ZStack {
      RimmedGlass(cornerRadius: PinGridLayout.diameter / 2, rimWidth: rim)
      Circle()
        .inset(by: rim)
        .fill(Color.primary.opacity(0.22))
        .opacity(isSelected ? 1 : 0)
      Circle()
        .inset(by: rim)
        .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
        .opacity(isActive ? 1 : 0)
      icon
        .frame(width: 16, height: 16)
        .opacity(pin.tabID == 0 ? Self.closedIconOpacity : 1)
    }
    .frame(width: PinGridLayout.diameter, height: PinGridLayout.diameter)
    .animation(.easeInOut(duration: 0.15), value: isSelected)
    .animation(.easeInOut(duration: 0.15), value: isActive)
  }

  @ViewBuilder private var icon: some View {
    if pin.isLoading {
      ProgressView()
        .controlSize(.small)
        .scaleEffect(0.75)
    } else if let favicon = pin.favicon {
      Image(nsImage: favicon)
        .renderingMode(favicon.isTemplate ? .template : .original)
        .resizable()
        .interpolation(.high)
    } else {
      Image(systemName: "globe")
        .foregroundStyle(.secondary)
    }
  }
}
