import AppKit

/// The window's title bar while the tab overlay's open: a strip across its
/// top, reaching as far below the traffic lights' capsule as the capsule is
/// from the window's top, with a handle beside the capsule. Dragging anywhere
/// on it moves the window.
final class WindowControlsBar: NSView {
  private static let rimWidth: CGFloat = 5
  /// The handle's width, as a share of the capsule's.
  private static let handleWidthShare: CGFloat = 2.0 / 3
  /// How far the pointer moves before a press off the glass becomes a drag.
  private static let dragThreshold: CGFloat = 3

  /// Behind the traffic lights, which stay in the title bar above it.
  let capsule = RimmedGlassView(rimWidth: rimWidth)
  /// Gets the clicks that don't drag, and the scrolling, as if the bar weren't
  /// there.
  weak var underlyingView: NSView?
  /// Whether it takes the pointer, which it stops doing as it starts to fade
  /// out.
  var isShown = false {
    didSet { window?.invalidateCursorRects(for: self) }
  }

  private let handle = RimmedGlassView(rimWidth: rimWidth)
  /// The traffic lights, where the pointer stays an arrow.
  private var buttonsFrame = NSRect.zero

  init() {
    super.init(frame: .zero)
    let hand = NSImageView(
      image: NSImage(
        systemSymbolName: "hand.raised.fingers.spread",
        accessibilityDescription: nil)!)
    hand.symbolConfiguration = .init(pointSize: 13, weight: .medium)
    hand.contentTintColor = .tertiaryLabelColor
    handle.contentView = hand
    addSubview(capsule)
    addSubview(handle)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Across the top of `bounds`, with the capsule around traffic lights at
  /// `buttonsFrame`, extending `padding` past them.
  func place(
    in bounds: NSRect, aroundButtons buttonsFrame: NSRect, padding: NSSize
  ) {
    let capsuleFrame = buttonsFrame.insetBy(
      dx: -padding.width, dy: -padding.height)
    let gap = bounds.maxY - capsuleFrame.maxY
    frame = NSRect(
      x: bounds.minX, y: capsuleFrame.minY - gap, width: bounds.width,
      height: capsuleFrame.height + 2 * gap)
    self.buttonsFrame = buttonsFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
    capsule.frame = capsuleFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
    capsule.cornerRadius = capsule.frame.height / 2
    handle.frame = NSRect(
      x: capsule.frame.maxX + GlassCapsule.spacing, y: capsule.frame.minY,
      width: (capsule.frame.width * Self.handleWidthShare).rounded(),
      height: capsule.frame.height)
    handle.cornerRadius = handle.frame.height / 2
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard isShown, super.hitTest(point) != nil else {
      return nil
    }
    return self
  }

  // It's in the title bar, where AppKit would otherwise drag the window
  // itself, and the click would never reach it.
  override var mouseDownCanMoveWindow: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func resetCursorRects() {
    guard isShown else {
      return
    }
    let buttons = buttonsFrame
    let rects = [
      NSRect(
        x: 0, y: buttons.maxY, width: bounds.width,
        height: bounds.height - buttons.maxY),
      NSRect(x: 0, y: 0, width: bounds.width, height: buttons.minY),
      NSRect(
        x: 0, y: buttons.minY, width: buttons.minX, height: buttons.height),
      NSRect(
        x: buttons.maxX, y: buttons.minY, width: bounds.width - buttons.maxX,
        height: buttons.height),
    ]
    for rect in rects {
      addCursorRect(rect, cursor: .openHand)
    }
  }

  /// The glass drags at once. Off it, a press drags only once the pointer
  /// moves, since a click there is the underlying view's.
  override func mouseDown(with event: NSEvent) {
    guard let window else {
      return
    }
    let start = event.locationInWindow
    let point = convert(start, from: nil)
    if capsule.frame.contains(point) || handle.frame.contains(point) {
      window.performDrag(with: event)
      return
    }
    window.trackEvents(
      matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity,
      mode: .eventTracking
    ) { [weak self] next, stop in
      MainActor.assumeIsolated {
        guard let self, let next else {
          stop.pointee = true
          return
        }
        if next.type == .leftMouseUp {
          stop.pointee = true
          self.underlyingView?.mouseDown(with: event)
        } else if hypot(
          next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
          > Self.dragThreshold
        {
          stop.pointee = true
          window.performDrag(with: event)
        }
      }
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    underlyingView?.rightMouseDown(with: event)
  }

  override func scrollWheel(with event: NSEvent) {
    underlyingView?.scrollWheel(with: event)
  }
}
