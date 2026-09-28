import AppKit
import FiberBridge

/// Swiping between pages, as Safari does it. The browser drives the progress
/// from AppKit's swipe tracking; after release this carries the swipe on, and
/// if it lands, the snapshot covers the page until the browser shows it.
@MainActor
final class HistorySwipe: NSObject {
  /// How far the page underneath moves over the whole swipe, as a fraction of
  /// the window's width.
  private static let parallax: CGFloat = 0.05
  /// How dark the page underneath is at its most covered.
  private static let underDim: Float = 0.15
  private static let shadowOpacity: Float = 0.22
  private static let fadeDuration: TimeInterval = 0.18
  /// Letting go, the swipe lands if it would coast past halfway: where it is,
  /// plus how far its speed would carry it in this long. Slowing to a stop
  /// near the end lands; a flick lands from anywhere; pulling back doesn't.
  private static let projection: CFTimeInterval = 0.25
  /// How far back the fingers' speed is measured from when they let go.
  private static let velocityWindow: CFTimeInterval = 0.08
  /// The stiffness of the (critically damped) spring that carries the swipe
  /// on after the user lets go: higher settles sooner.
  private static let settleStiffness: Double = 22

  let view = HistorySwipeView()
  /// Set by the owner, which adds `view` below or above the page area.
  var place: (_ view: NSView, _ above: Bool) -> Void = { _, _ in }

  private let pageArea: NSView
  private let page: NSView
  private var direction = FiberHistorySwipeDirection.back
  private var progress: CGFloat = 0
  /// The progress the browser reported lately, for the fingers' speed.
  private var samples: [(time: CFTimeInterval, progress: CGFloat)] = []
  /// Set once the user lets go, while the swipe carries itself on.
  private var settle: Settle?
  /// Set once the swipe has landed, while the snapshot covers the page.
  private var isCovering = false

  private struct Settle {
    let start: CFTimeInterval
    let from: CGFloat
    let target: CGFloat
    let velocity: CGFloat
    let link: CADisplayLink
    let completion: (Bool) -> Void
  }

  /// Moves `pageArea`, which holds the page. `page`, in it, is where the
  /// snapshot goes, the page's size and shape.
  init(pageArea: NSView, page: NSView) {
    self.pageArea = pageArea
    self.page = page
    super.init()
    view.isHidden = true
  }

  func begin(direction: FiberHistorySwipeDirection, snapshot: NSImage?) {
    reset()
    self.direction = direction
    place(view, direction == .forward)
    view.frame = pageArea.frame
    view.setPage(
      frame: page.frame, corners: page.layer?.maskedCorners ?? [],
      snapshot: snapshot)
    view.isHidden = false
    apply(progress: 0)
  }

  /// Where the user's fingers have the swipe, from the browser.
  func update(progress: Double) {
    guard settle == nil else {
      return
    }
    let now = CACurrentMediaTime()
    samples.removeAll { now - $0.time > Self.velocityWindow }
    samples.append((now, CGFloat(progress)))
    apply(progress: CGFloat(progress))
  }

  /// The user let go: the swipe lands or goes back, and calls `completion`
  /// with which once it's there.
  func release(_ completion: @escaping (Bool) -> Void) {
    guard settle == nil, let window = pageArea.window else {
      completion(false)
      return
    }
    let now = CACurrentMediaTime()
    samples.removeAll { now - $0.time > Self.velocityWindow }
    var velocity: CGFloat = 0
    if let first = samples.first, let last = samples.last,
      last.time > first.time
    {
      velocity = (last.progress - first.progress) / (last.time - first.time)
    }
    samples.removeAll()
    let landing = progress + velocity * Self.projection > 0.5
    let link = window.displayLink(target: self, selector: #selector(step(_:)))
    settle = Settle(
      start: now, from: progress, target: landing ? 1 : 0,
      velocity: velocity, link: link, completion: completion)
    link.add(to: .main, forMode: .common)
  }

  @objc private func step(_ link: CADisplayLink) {
    guard let settle else {
      link.invalidate()
      return
    }
    // A critically damped spring from where the user let go, at the
    // fingers' speed. It's done once it reaches the target.
    let omega = Self.settleStiffness
    let t = max(link.targetTimestamp - settle.start, 0)
    let d0 = Double(settle.from - settle.target)
    let d = (d0 + (Double(settle.velocity) + omega * d0) * t) * exp(-omega * t)
    if d * d0 <= 0 || abs(d) < 0.001 {
      apply(progress: settle.target)
      endSettle(landed: settle.target == 1)
    } else {
      apply(progress: settle.target + CGFloat(d))
    }
  }

  private func endSettle(landed: Bool) {
    guard let settle else {
      return
    }
    self.settle = nil
    settle.link.invalidate()
    settle.completion(landed)
  }

  private func apply(progress: CGFloat) {
    self.progress = min(max(progress, 0), 1)
    let width = view.bounds.width
    let p = self.progress
    let pageOffset: CGFloat
    let snapshotX: CGFloat
    let dim: Float
    switch direction {
    case .back:
      pageOffset = p * width
      snapshotX = -Self.parallax * width * (1 - p)
      dim = Self.underDim * Float(1 - p)
    case .forward:
      pageOffset = -Self.parallax * width * p
      snapshotX = (1 - p) * width
      dim = Self.underDim * Float(p)
    @unknown default:
      return
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    pageArea.layer?.sublayerTransform = CATransform3DMakeTranslation(
      pageOffset, 0, 0)
    // Going back, the shadow falls from the page's left edge onto the
    // snapshot; going forward, from the snapshot's left edge onto the page.
    let edge = direction == .back ? pageOffset : snapshotX
    view.layout(
      snapshotX: snapshotX, dim: dim, dimsSnapshot: direction == .back,
      shadowEdge: edge, shadowOpacity: p > 0 && p < 1 ? Self.shadowOpacity : 0)
    CATransaction.commit()
  }

  func end(navigating: Bool) {
    guard navigating else {
      reset()
      return
    }
    // The snapshot covers the page, which goes back in place under it.
    isCovering = true
    place(view, true)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    pageArea.layer?.sublayerTransform = CATransform3DIdentity
    view.layout(
      snapshotX: 0, dim: 0, dimsSnapshot: false, shadowEdge: 0,
      shadowOpacity: 0)
    CATransaction.commit()
  }

  /// The page swiped to is showing: the snapshot fades off it.
  func finish() {
    guard isCovering else {
      return
    }
    isCovering = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeDuration
      view.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isCovering, self.view.alphaValue == 0 else {
          return
        }
        self.reset()
      }
    }
  }

  /// Puts the page back and takes the swipe down, at once. A swipe still
  /// carrying itself on doesn't land.
  func reset() {
    endSettle(landed: false)
    samples.removeAll()
    isCovering = false
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    pageArea.layer?.sublayerTransform = CATransform3DIdentity
    CATransaction.commit()
    view.isHidden = true
    view.alphaValue = 1
    view.setPage(frame: .zero, corners: [], snapshot: nil)
  }
}

/// The swipe's layers, which HistorySwipe lays out.
final class HistorySwipeView: NSView {
  private let snapshotLayer = CALayer()
  private let dimLayer = CALayer()
  private let shadowLayer = CAGradientLayer()
  private let shadowWidth: CGFloat = 28
  /// Where the page is, in this view: where the snapshot goes.
  private var pageFrame = NSRect.zero
  private var pageCorners: CACornerMask = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = true
    // As the page was, at its size: a window resized since shows more or
    // less of it, with the background past it.
    snapshotLayer.contentsGravity = .topLeft
    snapshotLayer.masksToBounds = true
    dimLayer.backgroundColor = NSColor.black.cgColor
    dimLayer.opacity = 0
    for layer in [snapshotLayer, dimLayer] {
      layer.cornerRadius = BrowserWindowController.pageCornerRadius
      layer.cornerCurve = .continuous
    }
    shadowLayer.startPoint = CGPoint(x: 0, y: 0.5)
    shadowLayer.endPoint = CGPoint(x: 1, y: 0.5)
    shadowLayer.colors = [
      NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.cgColor,
    ]
    shadowLayer.opacity = 0
    for sublayer in [snapshotLayer, dimLayer, shadowLayer] {
      layer?.addSublayer(sublayer)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  /// A `nil` snapshot shows the window's background, as the page would be
  /// before it draws.
  func setPage(frame: NSRect, corners: CACornerMask, snapshot: NSImage?) {
    pageFrame = frame
    pageCorners = corners
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.maskedCorners = corners
    snapshotLayer.contents = snapshot?.cgImage(
      forProposedRect: nil, context: nil, hints: nil)
    snapshotLayer.contentsScale = window?.backingScaleFactor ?? 2
    effectiveAppearance.performAsCurrentDrawingAppearance {
      snapshotLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    CATransaction.commit()
  }

  /// `snapshotX` offsets the snapshot from the page's place. `dimsSnapshot`
  /// darkens the snapshot (going back) instead of the page under this view
  /// (going forward). `shadowEdge` is the x the shadow falls left from.
  func layout(
    snapshotX: CGFloat, dim: Float, dimsSnapshot: Bool, shadowEdge: CGFloat,
    shadowOpacity: Float
  ) {
    snapshotLayer.frame = pageFrame.offsetBy(dx: snapshotX, dy: 0)
    if dimsSnapshot {
      dimLayer.frame = snapshotLayer.frame
      dimLayer.maskedCorners = pageCorners
    } else {
      // Going forward, the darkening is on the page under the view, which
      // the snapshot covers from its left edge.
      dimLayer.frame = pageFrame
      dimLayer.frame.size.width = max(
        snapshotLayer.frame.minX - pageFrame.minX, 0)
      dimLayer.maskedCorners = pageCorners.intersection([
        .layerMinXMinYCorner, .layerMinXMaxYCorner,
      ])
    }
    dimLayer.opacity = dim
    shadowLayer.frame = NSRect(
      x: shadowEdge - shadowWidth, y: pageFrame.minY, width: shadowWidth,
      height: pageFrame.height)
    shadowLayer.opacity = shadowOpacity
  }
}
