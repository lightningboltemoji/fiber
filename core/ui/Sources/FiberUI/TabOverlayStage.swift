import AppKit

/// Everything in the tab overlay but the downloads, which sinks back and
/// darkens behind their open list, so the list stands in front of it. The
/// overlay's views go in `content`, laid out as if it weren't sunk; the
/// pointer reaches them where they're drawn.
@MainActor
final class TabOverlayStage: NSView {
  /// How small the content gets, toward the window's middle.
  private static let sunkScale: CGFloat = 0.98
  private static let sunkDimming: Float = 0.2
  private static let sinkKey = "tabOverlayStage.sink"

  /// Flipped, like the overlay.
  let content: NSView = FlippedView()
  private let dimView = DimView()
  private var isSunk = false

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    content.wantsLayer = true
    addSubview(content)
    addSubview(dimView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    content.frame = bounds
    dimView.frame = bounds
    // Toward the new middle.
    if isSunk {
      setSunk(true, duration: nil)
    }
  }

  /// Sinks the content, or brings it back, over `duration` (nil for at once),
  /// from wherever it is now. With Reduce Motion, it only darkens.
  func setSunk(_ sunk: Bool, duration: TimeInterval?) {
    isSunk = sunk
    dimView.setOpacity(sunk ? Self.sunkDimming : 0, duration: duration ?? 0)
    guard let layer = content.layer else {
      return
    }
    let reduceMotion = NSWorkspace.shared
      .accessibilityDisplayShouldReduceMotion
    let from = (layer.presentation() ?? layer).sublayerTransform
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.sublayerTransform =
      sunk && !reduceMotion
      ? Self.scale(Self.sunkScale, aboutMiddleOf: layer)
      : CATransform3DIdentity
    if let duration, !CATransform3DEqualToTransform(from, layer.sublayerTransform)
    {
      let animation = CASpringAnimation(perceptualDuration: duration, bounce: 0)
      animation.keyPath = "sublayerTransform"
      animation.fromValue = NSValue(caTransform3D: from)
      animation.toValue = NSValue(caTransform3D: layer.sublayerTransform)
      animation.duration = animation.settlingDuration
      layer.add(animation, forKey: Self.sinkKey)
    } else {
      layer.removeAnimation(forKey: Self.sinkKey)
    }
    CATransaction.commit()
  }

  /// The point in the content's layout that's drawn at `point`, in this view,
  /// as sunk as the content is now.
  func layoutPoint(drawnAt point: CGPoint) -> CGPoint {
    guard let layer = content.layer else {
      return point
    }
    let scale = (layer.presentation() ?? layer).sublayerTransform.m11
    guard scale > 0 else {
      return point
    }
    return CGPoint(
      x: bounds.midX + (point.x - bounds.midX) / scale,
      y: bounds.midY + (point.y - bounds.midY) / scale)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    super.hitTest(layoutPoint(drawnAt: point))
  }

  /// A sublayer transform is about the layer's anchor point, which AppKit
  /// sets.
  private static func scale(_ scale: CGFloat, aboutMiddleOf layer: CALayer)
    -> CATransform3D
  {
    let dx = (0.5 - layer.anchorPoint.x) * layer.bounds.width
    let dy = (0.5 - layer.anchorPoint.y) * layer.bounds.height
    var transform = CATransform3DMakeTranslation(dx, dy, 0)
    transform = CATransform3DScale(transform, scale, scale, 1)
    return CATransform3DTranslate(transform, -dx, -dy, 0)
  }
}

private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}
