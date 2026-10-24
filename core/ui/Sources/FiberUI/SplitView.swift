import AppKit
import FiberBridge

@objc @implementation extension FiberSplit {
  let leftTabID: Int
  let rightTabID: Int
  let ratio: Double
  let otherView: NSView?
  let otherIsNewTabPage: Bool

  init(
    leftTabID: Int, rightTabID: Int, ratio: Double, otherView: NSView?,
    otherIsNewTabPage: Bool
  ) {
    self.leftTabID = leftTabID
    self.rightTabID = rightTabID
    self.ratio = ratio
    self.otherView = otherView
    self.otherIsNewTabPage = otherIsNewTabPage
    super.init()
  }
}

/// A split's two pages side by side in the page area, with the divider in the
/// gap between them.
enum SplitLayout {
  static let gap: CGFloat = 10
  /// The least either page narrows to, in a page area that has room.
  static let minPageWidth: CGFloat = 280

  /// The left page and the right, for the left's share `ratio`.
  static func frames(in bounds: CGRect, ratio: Double)
    -> (left: CGRect, right: CGRect)
  {
    let room = max(bounds.width - gap, 0)
    let leftWidth = leftWidth((room * ratio).rounded(), room: room)
    var left = bounds
    left.size.width = leftWidth
    var right = bounds
    right.origin.x = bounds.minX + leftWidth + gap
    right.size.width = room - leftWidth
    return (left, right)
  }

  /// The left's share with the middle of the gap at `x`, or as near as the
  /// pages' least width allows.
  static func ratio(forGapAt x: CGFloat, in bounds: CGRect) -> Double {
    let room = max(bounds.width - gap, 1)
    return leftWidth(x - bounds.minX - gap / 2, room: room) / room
  }

  private static func leftWidth(_ width: CGFloat, room: CGFloat) -> CGFloat {
    let least = min(minPageWidth, room / 2)
    return min(max(width, least), room - least)
  }
}

/// Holds a tab's page: all of the page area, or a side of a split, rounded
/// like the window.
final class PagePane: NSView {
  private(set) weak var contents: NSView?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = true
    layer?.cornerCurve = .continuous
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// A page alone takes the page area's corners.
  var isRounded = false {
    didSet {
      layer?.cornerRadius =
        isRounded ? BrowserWindowController.pageCornerRadius : 0
    }
  }

  /// Shows `view` in place of the page it has.
  func setContents(_ view: NSView?) {
    guard view !== contents else {
      return
    }
    contents?.removeFromSuperview()
    contents = view
    guard let view else {
      return
    }
    view.frame = bounds
    view.autoresizingMask = [.width, .height]
    // Chrome hides a page made in the background (a ⌘-clicked link, a restored
    // tab) until its host shows it; hidden, it never draws.
    view.isHidden = false
    addSubview(view)
  }
}

/// Calls `onResize` once its subviews have resized with it.
final class ResizingView: NSView {
  var onResize: () -> Void = {}

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    super.resizeSubviews(withOldSize: oldSize)
    onResize()
  }
}

/// The gap between a split's pages, with a grip in its middle. Dragging it
/// moves the gap, and double-clicking it evens the pages out.
final class SplitDivider: NSView {
  private static let gripSize = NSSize(width: 4, height: 36)
  private static let hoveredGripSize = NSSize(width: 5, height: 52)

  /// Called with where the middle of the gap is going, in the superview, and
  /// whether the user's done.
  var onDrag: (_ x: CGFloat, _ isDone: Bool) -> Void = { _, _ in }
  var onReset: () -> Void = {}

  private let grip = CALayer()
  private var isHovered = false
  private var isDragging = false
  private var hasMoved = false
  /// From the gap's middle to where the pointer pressed it.
  private var grabOffset: CGFloat = 0

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    grip.cornerCurve = .continuous
    layer?.addSublayer(grip)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func layout() {
    super.layout()
    updateGrip(animated: false)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateGrip(animated: false)
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .columnResize)
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    updateGrip(animated: true)
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateGrip(animated: true)
  }

  override func mouseDown(with event: NSEvent) {
    guard event.clickCount < 2 else {
      onReset()
      return
    }
    isDragging = true
    hasMoved = false
    grabOffset = convert(event.locationInWindow, from: nil).x - bounds.midX
    updateGrip(animated: true)
  }

  override func mouseDragged(with event: NSEvent) {
    guard isDragging, let superview else {
      return
    }
    hasMoved = true
    onDrag(
      superview.convert(event.locationInWindow, from: nil).x - grabOffset,
      false)
  }

  override func mouseUp(with event: NSEvent) {
    guard isDragging, let superview else {
      return
    }
    isDragging = false
    if hasMoved {
      onDrag(
        superview.convert(event.locationInWindow, from: nil).x - grabOffset,
        true)
    }
    updateGrip(animated: true)
  }

  private func updateGrip(animated: Bool) {
    let isActive = isHovered || isDragging
    let size = isActive ? Self.hoveredGripSize : Self.gripSize
    CATransaction.begin()
    CATransaction.setDisableActions(!animated)
    CATransaction.setAnimationDuration(0.15)
    grip.frame = CGRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
      width: size.width, height: size.height)
    grip.cornerRadius = size.width / 2
    effectiveAppearance.performAsCurrentDrawingAppearance {
      grip.backgroundColor =
        (isActive ? NSColor.secondaryLabelColor : .tertiaryLabelColor).cgColor
    }
    CATransaction.commit()
  }
}
