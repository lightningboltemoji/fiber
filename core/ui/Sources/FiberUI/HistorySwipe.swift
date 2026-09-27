import AppKit
import FiberBridge

/// Swiping between pages, as Safari does it: the page follows the user's
/// fingers like a sheet of paper, with the page it's going to beside it (its
/// snapshot, or the window's background if there's none).
///
/// - Back: the page slides right, uncovering the previous page, which comes in
///   from a little to the left, darkened a little, under the page's shadow.
/// - Forward: the next page slides in from the right over this one, which
///   draws back a little to the left, darkening.
///
/// The browser drives the progress, from AppKit's swipe tracking, which
/// animates it on after the user lets go. Once the swipe lands on the other
/// page, the snapshot covers the page until the browser has it showing.
@MainActor
final class HistorySwipe {
  /// How far the page underneath moves over the whole swipe, as a fraction of
  /// the window's width.
  private static let parallax: CGFloat = 0.25
  /// How dark the page underneath is at its most covered.
  private static let underDim: Float = 0.15
  private static let shadowWidth: CGFloat = 28
  private static let shadowOpacity: Float = 0.22
  private static let fadeDuration: TimeInterval = 0.18

  /// Holds the snapshot, the darkening and the shadow. It goes under the page
  /// area going back and over it going forward; its owner adds it with
  /// place(_:).
  let view = HistorySwipeView()
  /// Where the swipe puts `view`, below or above the page area.
  var place: (_ view: NSView, _ above: Bool) -> Void = { _, _ in }

  private let pageArea: NSView
  private var direction = FiberHistorySwipeDirection.back
  private var progress: CGFloat = 0
  /// Set once the swipe has landed, while the snapshot covers the page.
  private var isCovering = false

  /// Moves `pageArea` (the page and the New Tab page over it).
  init(pageArea: NSView) {
    self.pageArea = pageArea
    view.isHidden = true
  }

  func begin(direction: FiberHistorySwipeDirection, snapshot: NSImage?) {
    reset()
    self.direction = direction
    view.setSnapshot(snapshot)
    place(view, direction == .forward)
    view.frame = pageArea.frame
    view.isHidden = false
    update(progress: 0)
  }

  func update(progress: Double) {
    self.progress = min(max(CGFloat(progress), 0), 1)
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

  /// Puts the page back and takes the swipe down, at once.
  func reset() {
    isCovering = false
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    pageArea.layer?.sublayerTransform = CATransform3DIdentity
    CATransaction.commit()
    view.isHidden = true
    view.alphaValue = 1
    view.setSnapshot(nil)
  }
}

/// The swipe's layers: the snapshot of the page swiped to, a darkening over
/// whichever page is underneath, and the shadow cast on it. Only drawn; the
/// swipe has the input.
final class HistorySwipeView: NSView {
  private let snapshotLayer = CALayer()
  private let dimLayer = CALayer()
  private let shadowLayer = CAGradientLayer()
  private let shadowWidth: CGFloat = 28

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = true
    snapshotLayer.contentsGravity = .resizeAspectFill
    snapshotLayer.masksToBounds = true
    dimLayer.backgroundColor = NSColor.black.cgColor
    dimLayer.opacity = 0
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

  /// `nil` shows the window's background, as the page would be before it
  /// draws.
  func setSnapshot(_ snapshot: NSImage?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if let snapshot {
      snapshotLayer.contents = snapshot
      snapshotLayer.contentsScale = window?.backingScaleFactor ?? 2
      snapshotLayer.backgroundColor = nil
    } else {
      snapshotLayer.contents = nil
      effectiveAppearance.performAsCurrentDrawingAppearance {
        snapshotLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
      }
    }
    CATransaction.commit()
  }

  /// Lays the layers out for a point in the swipe. `dimsSnapshot`: the
  /// darkening is over the snapshot (going back), not the page under this
  /// view (going forward). `shadowEdge` is the x the shadow falls left from.
  func layout(
    snapshotX: CGFloat, dim: Float, dimsSnapshot: Bool, shadowEdge: CGFloat,
    shadowOpacity: Float
  ) {
    let bounds = self.bounds
    snapshotLayer.frame = bounds.offsetBy(dx: snapshotX, dy: 0)
    dimLayer.frame = dimsSnapshot ? snapshotLayer.frame : bounds
    // Going forward, the darkening is on the page under the view, which the
    // snapshot covers from its left edge.
    if !dimsSnapshot {
      dimLayer.frame.size.width = max(snapshotX, 0)
    }
    dimLayer.opacity = dim
    shadowLayer.frame = NSRect(
      x: shadowEdge - shadowWidth, y: 0, width: shadowWidth,
      height: bounds.height)
    shadowLayer.opacity = shadowOpacity
  }
}
