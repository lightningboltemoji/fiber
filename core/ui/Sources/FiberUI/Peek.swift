import AppKit
import FiberBridge
import SwiftUI

@objc @implementation extension FiberPeek {
  let lowerTabID: Int
  let peekTabID: Int
  let lowerView: NSView?
  let peekView: NSView?

  init(lowerTabID: Int, peekTabID: Int, lowerView: NSView?, peekView: NSView?)
  {
    self.lowerTabID = lowerTabID
    self.peekTabID = peekTabID
    self.lowerView = lowerView
    self.peekView = peekView
    super.init()
  }
}

/// Where a peek's card and its buttons go in the page area.
enum PeekLayout {
  /// The buttons' size in a margin with room around them, down to the size
  /// in the narrowest margin, where they're over the card's edge by about 5pt.
  static let maxButtonSize: CGFloat = 32
  static let minButtonSize: CGFloat = 22
  private static let insetForMaxButtonSize: CGFloat = 40
  /// Between the buttons, at their largest.
  private static let maxButtonSpacing: CGFloat = 8
  /// The least between the buttons and the page area's edge.
  static let minButtonEdgeInset: CGFloat = 3
  /// The margin around the card, all round, from the least, in a page area
  /// whose shorter side is as narrow as a window gets, to the most.
  static let maxInset: CGFloat = 50
  static let minInset: CGFloat = 20
  private static let roomForMaxInset: CGFloat = 1000
  private static let roomForMinInset: CGFloat = 480
  /// The lower page's blur, and the opacity of the black over it.
  static let blurRadius: CGFloat = 20
  static let dimOpacity: Float = 0.2

  static func inset(in bounds: CGRect) -> CGFloat {
    let room = min(bounds.width, bounds.height)
    let progress =
      (room - roomForMinInset) / (roomForMaxInset - roomForMinInset)
    return (minInset + min(max(progress, 0), 1) * (maxInset - minInset))
      .rounded()
  }

  static func cardFrame(in bounds: CGRect) -> CGRect {
    let inset = inset(in: bounds)
    let frame = bounds.insetBy(dx: inset, dy: inset)
    return frame.isNull ? bounds : frame
  }

  static func buttonSize(inMargin margin: CGFloat) -> CGFloat {
    let progress = (margin - minInset) / (insetForMaxButtonSize - minInset)
    return (minButtonSize
      + min(max(progress, 0), 1) * (maxButtonSize - minButtonSize)).rounded()
  }

  static func buttonSpacing(forSize size: CGFloat) -> CGFloat {
    (maxButtonSpacing * size / maxButtonSize).rounded()
  }

  /// Close above Expand, beside the card's top-right corner, centered in the
  /// margin, or over the card's edge where the margin's too narrow for them.
  static func buttonsFrame(beside card: CGRect, in bounds: CGRect) -> CGRect {
    let margin = bounds.maxX - card.maxX
    let size = buttonSize(inMargin: margin)
    let spacing = buttonSpacing(forSize: size)
    let x = min(
      card.maxX + (margin - size) / 2, bounds.maxX - minButtonEdgeInset - size)
    return CGRect(
      x: x.rounded(), y: card.maxY - 2 * size - spacing, width: size,
      height: 2 * size + spacing)
  }

  /// What maps a layer laid out at `frame` onto `rect`, both in its
  /// superlayer, about the layer's `anchor`.
  static func transform(from frame: CGRect, to rect: CGRect, anchor: CGPoint)
    -> CATransform3D
  {
    guard frame.width > 0, frame.height > 0 else {
      return CATransform3DIdentity
    }
    let scaleX = rect.width / frame.width
    let scaleY = rect.height / frame.height
    let dx =
      rect.minX - frame.minX - anchor.x * frame.width * (1 - scaleX)
    let dy =
      rect.minY - frame.minY - anchor.y * frame.height * (1 - scaleY)
    return CATransform3DScale(
      CATransform3DMakeTranslation(dx, dy, 0), scaleX, scaleY, 1)
  }
}

/// Over a peek's lower page: darkens it, and takes the clicks and scrolls
/// meant for it. A click closes the peek.
final class PeekBackdrop: DimView {
  var onClick: () -> Void = {}
  /// Off as it fades out, letting the page have its clicks again.
  var takesClicks = false

  // DimView passes every click through.
  override func hitTest(_ point: NSPoint) -> NSView? {
    takesClicks && frame.contains(point) ? self : nil
  }

  // Under the title bar too, where a click would otherwise move the window.
  override var mouseDownCanMoveWindow: Bool { false }

  // AppKit passes on a click the card's page leaves to the view under it.
  override func mouseDown(with event: NSEvent) {
    if window?.contentView?.hitTest(event.locationInWindow) === self {
      onClick()
    }
  }

  override func rightMouseDown(with event: NSEvent) {}

  override func otherMouseDown(with event: NSEvent) {}

  override func scrollWheel(with event: NSEvent) {}

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .arrow)
  }
}

/// A peek's Close and Expand, round glass buttons one above the other.
final class PeekButtons: NSView {
  var onClose: () -> Void = {}
  var onExpand: () -> Void = {}

  private let model = PeekButtonsModel()

  override init(frame: NSRect) {
    super.init(frame: frame)
    let hostingView = NSHostingView(
      rootView: PeekButtonsView(
        model: model, onClose: { [weak self] in self?.onClose() },
        onExpand: { [weak self] in self?.onExpand() }))
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var mouseDownCanMoveWindow: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    model.isShown ? super.hitTest(point) : nil
  }

  /// As wide as each button (see PeekLayout.buttonsFrame(beside:in:)).
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    if model.size != newSize.width {
      model.size = newSize.width
    }
  }

  func setShown(_ shown: Bool, animated: Bool) {
    guard shown != model.isShown else {
      return
    }
    withAnimation(
      animated
        ? .spring(duration: 0.35, bounce: shown ? 0.3 : 0).slowMotion : nil
    ) {
      model.isShown = shown
    }
  }
}

@MainActor
@Observable
private final class PeekButtonsModel {
  var isShown = false
  var size = PeekLayout.maxButtonSize
}

private struct PeekButtonsView: View {
  let model: PeekButtonsModel
  let onClose: () -> Void
  let onExpand: () -> Void

  var body: some View {
    // Apart, not in a container, which would draw their symbols over its
    // glass whatever their opacity.
    VStack(spacing: PeekLayout.buttonSpacing(forSize: model.size)) {
      button("xmark", label: "Close", delay: 0, action: onClose)
      button(
        "arrow.up.left.and.arrow.down.right", label: "Expand", delay: 0.04,
        action: onExpand)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private func button(
    _ symbol: String, label: String, delay: TimeInterval,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(
          .system(
            size: (12 * model.size / PeekLayout.maxButtonSize).rounded(),
            weight: .semibold))
    }
    .buttonStyle(PeekButtonStyle(size: model.size))
    .foregroundStyle(.primary)
    .help(label)
    .accessibilityLabel(label)
    .scaleEffect(model.isShown ? 1 : 0.4)
    .opacity(model.isShown ? 1 : 0)
    .animation(
      .spring(duration: 0.35, bounce: 0.3).delay(model.isShown ? delay : 0)
        .slowMotion,
      value: model.isShown)
  }
}

/// Rimmed glass, like the split's spot, whose even rim reads as round over
/// any page, where plain glass's is lit at the top and bottom only. The
/// inner circle lights while the pointer's on it, and more while pressed.
private struct PeekButtonStyle: ButtonStyle {
  let size: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    PeekButtonFace(
      label: configuration.label, isPressed: configuration.isPressed,
      size: size)
  }
}

private struct PeekButtonFace: View {
  let label: ButtonStyleConfiguration.Label
  let isPressed: Bool
  let size: CGFloat
  @State private var isHovered = false

  var body: some View {
    // As thick for its size as a glass capsule's.
    let rim = (GlassCapsule.rimWidth * size / GlassCapsule.height).rounded()
    ZStack {
      RimmedGlass(cornerRadius: size / 2, rimWidth: rim)
      Circle()
        .inset(by: rim)
        .fill(Color.primary.opacity(isPressed ? 0.22 : isHovered ? 0.1 : 0))
      label
    }
    .frame(width: size, height: size)
    .contentShape(Circle())
    .scaleEffect(isPressed ? 0.92 : 1)
    .animation(
      .spring(duration: 0.25, bounce: 0.4).slowMotion, value: isPressed)
    .animation(.easeInOut(duration: 0.15).slowMotion, value: isHovered)
    .onHover { isHovered = $0 }
  }
}

/// A peek's favicon, tucked into the corner of the icon of the tab it's over,
/// in the tab overlay's rows and pins.
struct PeekBadge: View {
  static let size: CGFloat = 10

  let favicon: NSImage?

  var body: some View {
    Group {
      if let favicon {
        Image(nsImage: favicon)
          .renderingMode(favicon.isTemplate ? .template : .original)
          .resizable()
          .interpolation(.high)
      } else {
        Image(systemName: "globe")
          .resizable()
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: Self.size, height: Self.size)
    .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    .padding(1.5)
    .background(
      .regularMaterial,
      in: RoundedRectangle(cornerRadius: 4, style: .continuous)
    )
    .offset(x: 5, y: 5)
    .accessibilityHidden(true)
  }
}
