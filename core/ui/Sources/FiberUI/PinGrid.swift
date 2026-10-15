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

  /// The circle of the pin at `index`.
  static func frame(of index: Int, width: CGFloat) -> CGRect {
    CGRect(
      origin: origin(of: index, width: width),
      size: CGSize(width: diameter, height: diameter))
  }

  static let beadDiameter: CGFloat = 18
  /// How far around its glass the bead takes the pointer, short of the pins
  /// around it.
  static let beadReach: CGFloat = 11
  /// How close the bead and its pin's glass come before they blend. Less than
  /// the gap between them in the pocket, so it breaks away.
  static let beadBlend: CGFloat = 15

  /// The center of an open pin's bead, in the pocket at the pin's top-left
  /// where it and three others meet: the most room between pins, and on no
  /// straight line from one to another.
  static func beadCenter(of index: Int, width: CGFloat) -> CGPoint {
    let frame = frame(of: index, width: width)
    return CGPoint(x: frame.midX - step / 2, y: frame.midY - step / 2)
  }

  static func beadFrame(of index: Int, width: CGFloat) -> CGRect {
    let center = beadCenter(of: index, width: width)
    return CGRect(
      x: center.x - beadReach, y: center.y - beadReach,
      width: 2 * beadReach, height: 2 * beadReach)
  }

  /// The pin at `point`, with the bead of the pin at `bead` out, and which
  /// part of it.
  static func hit(at point: CGPoint, count: Int, bead: Int?, width: CGFloat)
    -> (index: Int, part: PinPart)?
  {
    for index in 0..<count {
      let frame = frame(of: index, width: width)
      let center = CGPoint(x: frame.midX, y: frame.midY)
      if hypot(point.x - center.x, point.y - center.y) <= diameter / 2 {
        return (index, .icon)
      }
      guard index == bead else {
        continue
      }
      let beadCenter = beadCenter(of: index, width: width)
      if hypot(point.x - beadCenter.x, point.y - beadCenter.y) <= beadReach {
        return (index, .bead)
      }
      if distance(from: point, toSegmentFrom: center, to: beadCenter)
        <= beadReach
      {
        return (index, .bridge)
      }
    }
    return nil
  }

  private static func distance(
    from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint
  ) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let t = min(
      max(
        ((point.x - start.x) * dx + (point.y - start.y) * dy)
          / (dx * dx + dy * dy), 0), 1)
    return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
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

/// An open pin's bead, out while the pointer is on the pin or Option is held
/// with it selected. It takes the pin's tab back to the pinned page, and once
/// the tab is there, closes it.
struct PinBead: Equatable {
  let pinID: String
  var action: PinBeadAction
  /// Whether Option brought it out, rather than the pointer.
  let isFromKeyboard: Bool
}

enum PinBeadAction: Equatable {
  case reset, close
}

/// A part of a pin: its circle, its bead, or the space between them, which
/// keeps the bead out but presses nothing.
enum PinPart: Equatable {
  case icon, bead, bridge
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
  private static let moveAnimation = Animation.spring(
    duration: 0.3, bounce: 0.15)

  var body: some View {
    let width = model.gridWidth
    let shown = model.shownPins
    let span = model.motionSpan
    PinGridStack {
      ForEach(model.pins, id: \.pinID) { pin in
        let isDragged = model.pinDrag?.pinID == pin.pinID
        let index = model.pins.firstIndex { $0.pinID == pin.pinID } ?? 0
        let slot = shown.firstIndex { $0.pinID == pin.pinID } ?? index
        let bead = model.pinBead?.pinID == pin.pinID ? model.pinBead : nil
        let origin = PinGridLayout.origin(
          of: isDragged ? index : slot, width: width)
        let offset = isDragged ? model.pinDrag?.offset ?? .zero : .zero
        let delay = model.motionDelay(ofPin: index)
        PinCircle(
          pin: pin, isActive: pin.tabID != 0 && pin.tabID == model.activeTabID,
          isSelected: model.selection == .pin(pin.pinID) && model.pinDrag == nil,
          bead: bead?.action,
          isBeadFocused: bead.map {
            $0.isFromKeyboard || model.focusedPinPart == .bead
          } ?? false
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
        .zIndex(isDragged ? 2 : bead != nil ? 1 : 0)
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
            model.onCloseTab(pin.tabID)
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
/// open in the window, and ringed while its tab is the active one. Its bead
/// buds off its glass into the pocket at its top-left, and breaks away.
private struct PinCircle: View {
  let pin: FiberPinState
  let isActive: Bool
  let isSelected: Bool
  /// What its bead does, while it's out.
  let bead: PinBeadAction?
  let isBeadFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let rim = GlassCapsule.rimWidth
    let diameter = PinGridLayout.diameter
    let isOpen = pin.tabID != 0
    let outer = RoundedRectangle(cornerRadius: diameter / 2, style: .continuous)
    let inner = outer.inset(by: rim)
    ZStack {
      // RimmedGlass's inner glass. Its outer glass is in the bead's container.
      Color.clear
        .glassEffect(
          .regular,
          in: RoundedRectangle(
            cornerRadius: diameter / 2 - rim, style: .continuous)
        )
        .padding(rim)
      inner
        .fill(Color.primary.opacity(0.22))
        .opacity(isSelected ? 1 : 0)
      inner
        .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
        .opacity(isActive ? 1 : 0)
      icon
        .frame(width: 16, height: 16)
      Circle()
        .fill(Color.primary.opacity(0.75))
        .frame(width: 3.5, height: 3.5)
        .offset(y: 11)
        .scaleEffect(isOpen ? 1 : 0.2)
        .opacity(isOpen ? 1 : 0)
    }
    .frame(width: diameter, height: diameter)
    // Glass in one container blends where it comes close, so the bead leaves
    // the pin as a drop drawn out of its glass.
    .background {
      GlassEffectContainer(spacing: PinGridLayout.beadBlend) {
        ZStack {
          Color.clear
            .frame(width: diameter, height: diameter)
            .glassEffect(.regular, in: outer)
          // The symbol is the glass's content, which a container draws over.
          ZStack {
            Color.clear
            if let bead {
              PinBeadGlyph(action: bead, isFocused: isBeadFocused)
                .transition(.beadGlyph)
            }
          }
          .glassEffect(.regular, in: Circle())
          .modifier(BeadBud(progress: bead != nil ? 1 : 0))
            .animation(
              reduceMotion
                ? nil
                : bead != nil
                  ? .spring(duration: 0.5, bounce: 0.35).slowMotion
                  : .spring(duration: 0.3, bounce: 0).slowMotion,
              value: bead != nil)
        }
        // Centered on the pin, reaching its pocket.
        .frame(width: 2 * PinGridLayout.step, height: 2 * PinGridLayout.step)
      }
    }
    .animation(.easeInOut(duration: 0.15).slowMotion, value: isSelected)
    .animation(.easeInOut(duration: 0.15).slowMotion, value: isActive)
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

/// The bead's symbol, over its glass. Back's arrow turns back once as the
/// pointer comes onto it, and pressed, spins on round into Close's cross.
private struct PinBeadGlyph: View {
  let action: PinBeadAction
  let isFocused: Bool

  var body: some View {
    let isReset = action == .reset
    ZStack {
      Circle()
        .fill(Color.primary.opacity(isFocused ? 0.16 : 0))
        .padding(2)
      Image(systemName: "arrow.counterclockwise")
        .rotationEffect(.degrees(isFocused ? -360 : 0))
        .animation(
          isFocused ? .spring(duration: 0.6, bounce: 0.25).slowMotion : nil,
          value: isFocused
        )
        .scaleEffect(isReset ? 1 : 0.3)
        .opacity(isReset ? 1 : 0)
      Image(systemName: "xmark")
        .scaleEffect(isReset ? 0.3 : 1)
        .opacity(isReset ? 0 : 1)
    }
    .font(.system(size: 9, weight: .bold))
    .foregroundStyle(isFocused ? .primary : .secondary)
    .rotationEffect(.degrees(isReset ? 0 : -360))
    .animation(.spring(duration: 0.55, bounce: 0.3).slowMotion, value: action)
    .animation(.easeInOut(duration: 0.12).slowMotion, value: isFocused)
  }
}

/// A bead on its way out of its pin's glass: at 0, small at the pin's center
/// and lost in its glass, and at 1, out in its pocket. Laid out afresh each
/// frame, since an offset here doesn't animate.
private struct BeadBud: ViewModifier, Animatable {
  var progress: CGFloat

  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let size = PinGridLayout.beadDiameter * (0.4 + 0.6 * progress)
    let center = PinGridLayout.step * (1 - progress / 2)
    content
      .frame(width: size, height: size)
      .position(x: center, y: center)
  }
}

private struct BeadFade: ViewModifier {
  let opacity: Double
  let scale: CGFloat

  func body(content: Content) -> some View {
    content.opacity(opacity).scaleEffect(scale)
  }
}

extension AnyTransition {
  /// Its symbol shows as the bead breaks away, and goes at once as it's drawn
  /// back, since a symbol on its way out stays where the bead was.
  @MainActor fileprivate static var beadGlyph: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: BeadFade(opacity: 0, scale: 0.4),
        identity: BeadFade(opacity: 1, scale: 1)
      ).animation(.spring(duration: 0.35, bounce: 0.4).delay(0.15).slowMotion),
      removal: .modifier(
        active: BeadFade(opacity: 0, scale: 0.6),
        identity: BeadFade(opacity: 1, scale: 1)
      ).animation(.easeIn(duration: 0.06).slowMotion))
  }
}
