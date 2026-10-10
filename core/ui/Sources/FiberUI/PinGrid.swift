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
  static let step = diameter + spacing

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

  /// Whether `point` is on a circle or in the gaps between them, rather than
  /// past the last one.
  static func covers(_ point: CGPoint, count: Int, width: CGFloat) -> Bool {
    let columns = columns(width: width)
    let column = Int(((point.x + spacing / 2) / step).rounded(.down))
    let row = Int(((spacing / 2 - point.y) / step).rounded(.down))
    return (0..<columns).contains(column) && row >= 0
      && row * columns + column < count
  }

  /// How far an open pin's capsule reaches past its circle for each of its
  /// buttons: Back on the left, Close on the right.
  static let buttonWidth: CGFloat = 30

  /// The circle of the pin at `index`, or its capsule if it's `open`. The open
  /// pin's icon stays where its circle was, and the rest of its row parts
  /// around it.
  static func frame(of index: Int, open: OpenPin?, width: CGFloat) -> CGRect {
    var frame = CGRect(
      origin: origin(of: index, width: width),
      size: CGSize(width: diameter, height: diameter))
    guard let open else {
      return frame
    }
    let back = open.hasBack ? buttonWidth : 0
    if index == open.index {
      frame.origin.x -= back
      frame.size.width += back + buttonWidth
    } else if index / columns(width: width) == open.index / columns(width: width)
    {
      frame.origin.x += index < open.index ? -back : buttonWidth
    }
    return frame
  }

  /// The pin at `point`, placed as frame(of:open:width:) places it, and which
  /// part of it.
  static func hit(at point: CGPoint, count: Int, open: OpenPin?, width: CGFloat)
    -> (index: Int, part: PinPart)?
  {
    let radius = diameter / 2
    for index in 0..<count {
      let frame = frame(of: index, open: open, width: width)
      // Within a radius of the line between its ends' centers.
      let x = min(max(point.x, frame.minX + radius), frame.maxX - radius)
      guard hypot(point.x - x, point.y - frame.midY) <= radius else {
        continue
      }
      guard let open, open.index == index else {
        return (index, .icon)
      }
      let icon = frame.minX + (open.hasBack ? buttonWidth : 0)
      return (
        index,
        point.x < icon ? .back : point.x > icon + diameter ? .close : .icon
      )
    }
    return nil
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

/// An open pin grown into a capsule with its buttons, while the pointer is on
/// it or Option is held with it selected. Back is there only if its tab has
/// left the pinned page.
struct PinExpansion: Equatable {
  let pinID: String
  let hasBack: Bool
  /// Whether Option opened it, rather than the pointer.
  let isFromKeyboard: Bool
}

/// The open pin, for PinGridLayout.
struct OpenPin: Equatable {
  let index: Int
  let hasBack: Bool
}

/// A part of a pin: its icon, or one of an open pin's buttons.
enum PinPart: Equatable {
  case icon, back, close
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
/// rest make room where it would go, and while one's open into its capsule,
/// its row parts around it.
struct PinGrid: View {
  let model: TabOverlayModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let moveAnimation = Animation.spring(
    duration: 0.3, bounce: 0.15)
  static let expandAnimation = Animation.spring(duration: 0.32, bounce: 0.2)

  var body: some View {
    let width = model.gridWidth
    let shown = model.shownPins
    let span = model.motionSpan
    PinGridStack {
      ForEach(model.pins, id: \.pinID) { pin in
        let isDragged = model.pinDrag?.pinID == pin.pinID
        let index = model.pins.firstIndex { $0.pinID == pin.pinID } ?? 0
        let slot = shown.firstIndex { $0.pinID == pin.pinID } ?? index
        let expansion =
          model.pinExpansion?.pinID == pin.pinID ? model.pinExpansion : nil
        let origin = PinGridLayout.frame(
          of: isDragged ? index : slot, open: model.openPin, width: width
        ).origin
        let offset = isDragged ? model.pinDrag?.offset ?? .zero : .zero
        let delay = model.motionDelay(ofPin: index)
        PinCircle(
          pin: pin, isActive: pin.tabID != 0 && pin.tabID == model.activeTabID,
          isSelected: model.selection == .pin(pin.pinID) && model.pinDrag == nil,
          expansion: expansion,
          focusedPart: expansion == nil ? nil : model.focusedPinPart
        )
        // Not animation(_:body:), which doesn't animate an offset.
        .offset(y: model.isOpen || reduceMotion ? 0 : -TabOverlayMotion.travel)
        .animation(
          TabOverlayMotion.animation(
            .offset, delay: delay, span: span, isOpening: model.isOpen),
          value: model.isOpen)
        .opacity(model.isOpen || reduceMotion ? 1 : 0)
        .animation(
          TabOverlayMotion.animation(
            .opacity, delay: delay, span: span, isOpening: model.isOpen),
          value: model.isOpen)
        // A dragged pin follows the pointer from its place. Its place takes the
        // drag rather than an offset, which would animate apart from the place
        // and swing a dropped pin past it.
        .place(
          at: CGPoint(x: origin.x + offset.width, y: origin.y + offset.height))
        .zIndex(isDragged ? 2 : expansion != nil ? 1 : 0)
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
        .accessibilityAction(named: "Back to Pinned Page") {
          if pin.tabID != 0 {
            model.onResetPin(pin.pinID)
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
    // Pins glide to make room, a dropped pin settles into its place, and the
    // rest close or open up as pins come and go. Set on the grid, since a pin's
    // place animates with the grid's transaction rather than its own.
    .animation(Self.moveAnimation.slowMotion, value: shown.map(\.pinID))
    .animation(Self.moveAnimation.slowMotion, value: model.pinDrag?.pinID)
    .animation(Self.expandAnimation.slowMotion, value: model.pinExpansion)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Pinned")
  }
}

/// Puts each view's top-left corner at its place (see place(at:)), from the
/// stack's bottom-left corner. Unlike a ZStack, it doesn't grow to hold them,
/// so a pin dragged or opened past its edges moves none of the others.
private struct PinGridStack: Layout {
  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    proposal.replacingUnspecifiedDimensions(by: .zero)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
    cache: inout ()
  ) {
    for subview in subviews {
      let origin = subview[PinPlace.self]
      subview.place(
        at: CGPoint(x: bounds.minX + origin.x, y: bounds.maxY + origin.y),
        anchor: .topLeading, proposal: .unspecified)
    }
  }
}

private struct PinPlace: LayoutValueKey {
  static let defaultValue = CGPoint.zero
}

extension View {
  /// Lays the view out with its top-left corner at `origin` in a
  /// PinGridStack, so its own effects (a transition's scale) center on it.
  fileprivate func place(at origin: CGPoint) -> some View {
    layoutValue(key: PinPlace.self, value: origin)
  }
}

extension AnyTransition {
  /// A pin pops in, zooming up from small and past its size before it
  /// settles, and pops out, swelling as it fades.
  @MainActor fileprivate static var pinPop: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: PinPop(scale: 0.3, opacity: 0, blur: 6),
        identity: PinPop(scale: 1, opacity: 1, blur: 0)
      ).animation(.spring(duration: 0.5, bounce: 0.5).slowMotion),
      removal: .modifier(
        active: PinPop(scale: 1.4, opacity: 0, blur: 3),
        identity: PinPop(scale: 1, opacity: 1, blur: 0)
      ).animation(.easeOut(duration: PinGridLayout.popOutDuration).slowMotion))
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
      withAnimation(.easeOut(duration: Self.duration).slowMotion) { travel = 1 }
      withAnimation(.easeIn(duration: Self.duration).slowMotion) { fade = 1 }
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

/// A pin: its page's icon in a circle of glass, with a dot under it while it's
/// open in the window, and ringed while its tab is the active one. Open into
/// its capsule, it has Back to its left, if its tab has left the pinned page,
/// and Close to its right.
private struct PinCircle: View {
  let pin: FiberPinState
  let isActive: Bool
  let isSelected: Bool
  let expansion: PinExpansion?
  /// The part the pointer is on, or Option and the arrow keys chose.
  let focusedPart: PinPart?

  var body: some View {
    let rim = GlassCapsule.rimWidth
    let diameter = PinGridLayout.diameter
    let back = expansion?.hasBack == true ? PinGridLayout.buttonWidth : 0
    let close = expansion != nil ? PinGridLayout.buttonWidth : 0
    let isOpen = pin.tabID != 0
    let shape = RoundedRectangle(cornerRadius: diameter / 2, style: .continuous)
    ZStack {
      RimmedGlass(cornerRadius: diameter / 2, rimWidth: rim)
      shape
        .inset(by: rim)
        .fill(Color.primary.opacity(0.22))
        .opacity(isSelected && expansion == nil ? 1 : 0)
      shape
        .inset(by: rim)
        .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
        .opacity(isActive ? 1 : 0)
      HStack(spacing: 0) {
        PinButton(
          symbol: "arrow.counterclockwise", isFocused: focusedPart == .back,
          turnsBack: true
        )
        // Centered in the capsule's round end.
        .offset(x: 3)
        .frame(width: back)
        .opacity(back > 0 ? 1 : 0)
        ZStack {
          Circle()
            .inset(by: rim + 1)
            .fill(Color.primary.opacity(focusedPart == .icon ? 0.16 : 0))
          icon
            .frame(width: 16, height: 16)
          Circle()
            .fill(Color.primary.opacity(0.75))
            .frame(width: 3.5, height: 3.5)
            .offset(y: 11)
            .scaleEffect(isOpen ? 1 : 0.2)
            .opacity(isOpen ? 1 : 0)
        }
        .frame(width: diameter)
        PinButton(symbol: "xmark", isFocused: focusedPart == .close)
          .offset(x: -3)
          .frame(width: close)
          .opacity(close > 0 ? 1 : 0)
      }
      .frame(height: diameter)
      .clipped()
    }
    .frame(width: back + diameter + close, height: diameter)
    .animation(.easeInOut(duration: 0.15).slowMotion, value: isSelected)
    .animation(.easeInOut(duration: 0.15).slowMotion, value: isActive)
    .animation(.easeInOut(duration: 0.12).slowMotion, value: focusedPart)
    .animation(.spring(duration: 0.35, bounce: 0.4).slowMotion, value: isOpen)
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

/// A button at one end of an open pin's capsule. Back's arrow turns back once
/// as it's focused.
private struct PinButton: View {
  let symbol: String
  let isFocused: Bool
  var turnsBack = false

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.primary.opacity(isFocused ? 0.14 : 0))
        .frame(width: 22, height: 22)
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(isFocused ? .primary : .secondary)
        .rotationEffect(.degrees(turnsBack && isFocused ? -360 : 0))
        .animation(
          isFocused ? .spring(duration: 0.6, bounce: 0.25).slowMotion : nil,
          value: isFocused)
    }
  }
}
