import AppKit

/// The strip along the window's right edge that the page stops short of, where
/// the tab picker sits, so the page's scrollbar and anything else on its edge
/// stay clear of the picker. The strip continues the page: it shows the page's
/// edge, mirrored and blurred. Dragging it moves the window; scrolling over it
/// scrolls the page.
final class PageGutter: WindowDragArea {
  nonisolated static let width: CGFloat = 8

  private enum Metrics {
    static let blurRadius: CGFloat = 6
    /// How far in from the page's edge the mirror starts: past the page's
    /// scrollbar (at most 16pt wide on macOS), so it doesn't show in the
    /// gutter.
    static let mirrorInset: CGFloat = 16
  }

  /// The tab's web contents, which fills the page area. The gutter mirrors
  /// it.
  var contentsView: NSView? {
    didSet {
      guard contentsView !== oldValue else {
        return
      }
      NotificationCenter.default.removeObserver(
        self, name: NSView.frameDidChangeNotification, object: oldValue)
      if let contentsView {
        NotificationCenter.default.addObserver(
          self, selector: #selector(contentsFrameDidChange(_:)),
          name: NSView.frameDidChangeNotification, object: contentsView)
      }
      watchContentsLayers()
      layoutMirror()
    }
  }

  /// What the blur samples: wider than the gutter by the blur's reach, so the
  /// blur doesn't fade at the gutter's edges. It holds the page twice: as it
  /// is (reaching into the gutter's left edge) and flipped about the page's
  /// edge (filling the gutter and past it).
  private let stage = CALayer()
  /// Maps x to -x about the gutter's left edge, where the page ends.
  private let flipLayer = CALayer()
  private let pageSpace = CALayer()
  private let flippedPageSpace = CALayer()
  private var observations: [NSKeyValueObservation] = []
  private var isWatchScheduled = false
  private var contextID: UInt32?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layerUsesCoreImageFilters = true
    let layer = self.layer!
    layer.masksToBounds = true

    stage.anchorPoint = .zero
    stage.masksToBounds = true
    stage.filters = [
      CIFilter(
        name: "CIGaussianBlur",
        parameters: [kCIInputRadiusKey: Metrics.blurRadius])!
    ]
    flipLayer.anchorPoint = .zero
    flipLayer.sublayerTransform = CATransform3DMakeScale(-1, 1, 1)
    // Chrome puts the page's layer at the top left of its view, in a flipped
    // layer (ui::DisplayCALayerTree), so each copy's origin is the page's
    // top-left corner.
    for space in [pageSpace, flippedPageSpace] {
      space.anchorPoint = .zero
      space.isGeometryFlipped = true
    }
    flipLayer.addSublayer(flippedPageSpace)
    stage.addSublayer(pageSpace)
    stage.addSublayer(flipLayer)
    layer.addSublayer(stage)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // The page and the gutter move and resize together, in either order.
  @objc private func contentsFrameDidChange(_ notification: Notification) {
    layoutMirror()
  }

  override func setFrameOrigin(_ newOrigin: NSPoint) {
    super.setFrameOrigin(newOrigin)
    layoutMirror()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    layoutMirror()
  }

  // MARK: Scrolling

  /// Scrolls the page: passes the event to the page's view beside the
  /// pointer.
  override func scrollWheel(with event: NSEvent) {
    guard let contentsView, let root = window?.contentView else {
      return
    }
    let edge = contentsView.convert(
      NSPoint(x: contentsView.bounds.maxX - 1, y: 0), to: nil
    ).x
    // The content view's superview (the frame view) has window coordinates.
    root.hitTest(NSPoint(x: edge, y: event.locationInWindow.y))?
      .scrollWheel(with: event)
  }

  // MARK: Mirror

  /// Follows the layer Chrome shows the page with: a CALayerHost, which shows
  /// a layer tree the GPU process draws. The mirror is two more hosts of the
  /// same tree. Chrome replaces its host when that tree changes, and a
  /// cross-process navigation replaces the view holding it, so this watches
  /// the contents' layers for sublayers coming and going.
  private func watchContentsLayers() {
    observations = []
    var host: CALayer?
    func watch(_ layer: CALayer) {
      if NSStringFromClass(type(of: layer)) == "CALayerHost" {
        host = host ?? layer
        return
      }
      observations.append(
        layer.observe(\.sublayers) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.scheduleWatch() }
        })
      layer.sublayers?.forEach(watch)
    }
    if let layer = contentsView?.layer {
      watch(layer)
    }
    mirror(contextID: host?.value(forKey: "contextId") as? UInt32)
  }

  /// Watches again once the change that triggered this is done (and not
  /// from inside an observation that watching again tears down).
  private func scheduleWatch() {
    guard !isWatchScheduled else {
      return
    }
    isWatchScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        self?.isWatchScheduled = false
        self?.watchContentsLayers()
      }
    }
  }

  private func mirror(contextID: UInt32?) {
    guard contextID != self.contextID else {
      return
    }
    self.contextID = contextID
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for space in [pageSpace, flippedPageSpace] {
      space.sublayers = contextID.flatMap(Self.makeLayerHost).map { [$0] }
    }
    CATransaction.commit()
  }

  private func layoutMirror() {
    guard let contentsView, contentsView.window === window else {
      return
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let reach = 3 * Metrics.blurRadius
    stage.frame = bounds.insetBy(dx: -reach, dy: 0)
    // The page, relative to the gutter's left edge.
    let page = convert(contentsView.bounds, from: contentsView)
    // In the stage, the gutter's left edge is at x = reach.
    pageSpace.frame = page.offsetBy(dx: reach, dy: 0)
    flipLayer.frame = CGRect(x: reach, y: 0, width: 0, height: bounds.height)
    // Flipped, the page's content d left of this frame's right edge shows d
    // right of the gutter's left edge.
    flippedPageSpace.frame = page.offsetBy(dx: Metrics.mirrorInset, dy: 0)
    CATransaction.commit()
  }

  private static func makeLayerHost(_ contextID: UInt32) -> CALayer? {
    guard let hostClass = NSClassFromString("CALayerHost") as? CALayer.Type
    else {
      return nil
    }
    let host = hostClass.init()
    host.anchorPoint = .zero
    host.setValue(contextID, forKey: "contextId")
    return host
  }
}
