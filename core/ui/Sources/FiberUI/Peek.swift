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
  static let buttonSize: CGFloat = 32
  /// Between the buttons, and between them and the card.
  static let buttonSpacing: CGFloat = 8
  /// The lower page's blur, and the opacity of the black over it.
  static let blurRadius: CGFloat = 20
  static let dimOpacity: Float = 0.2

  /// Inset from the page area, with room in the side margins for the buttons.
  static func cardFrame(in bounds: CGRect) -> CGRect {
    let side = max(
      buttonSize + 2 * buttonSpacing, (bounds.width * 0.06).rounded())
    let top = max(2 * buttonSpacing, (bounds.height * 0.04).rounded())
    let frame = bounds.insetBy(dx: side, dy: top)
    return frame.isNull ? bounds : frame
  }

  /// Close above Expand, in the margin beside the card's top-right corner.
  static func buttonsFrame(beside card: CGRect) -> CGRect {
    CGRect(
      x: card.maxX + buttonSpacing,
      y: card.maxY - 2 * buttonSize - buttonSpacing, width: buttonSize,
      height: 2 * buttonSize + buttonSpacing)
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

  override func hitTest(_ point: NSPoint) -> NSView? {
    takesClicks ? super.hitTest(point) : nil
  }

  override func mouseDown(with event: NSEvent) {
    onClick()
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
}

private struct PeekButtonsView: View {
  let model: PeekButtonsModel
  let onClose: () -> Void
  let onExpand: () -> Void

  var body: some View {
    // Apart, not in a container, which would draw their symbols over its
    // glass whatever their opacity.
    VStack(spacing: PeekLayout.buttonSpacing) {
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
        .font(.system(size: 12, weight: .semibold))
        .frame(width: PeekLayout.buttonSize, height: PeekLayout.buttonSize)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .glassEffect(.regular.interactive(), in: Circle())
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
