import AppKit

/// Blurs a window's page and darkens the window over it, while the window
/// waits on the user: as they hold Command-Q to quit, say. What the window is
/// waiting for shows over the veil.
///
/// The blur is a filter on the page's views rather than a backdrop over them:
/// a backdrop only samples what's inside the window, so its blur darkens
/// toward the window's edges. The filter is only there while the veil is,
/// since it costs an offscreen pass over the page every frame.
@MainActor
final class Veil {
  /// A fully drawn veil's blur radius, and the opacity of its black.
  private static let blurRadius: CGFloat = 24
  private static let dimOpacity: Float = 0.6
  private static let blurKeyPath = "filters.blur.inputRadius"

  /// Darkens the window. Its owner puts it over the page and the controls.
  let dimView = VeilDimView()
  /// How far the veil is drawn, from 0 (lifted) to 1, once any animation
  /// ends.
  private(set) var amount: CGFloat = 0
  private let blurredView: NSView
  /// Counts changes to `amount`, so a lift that finishes after the veil was
  /// drawn again leaves the filter on.
  private var generation = 0

  /// Blurs `view` (the page area) when drawn.
  init(blurring view: NSView) {
    blurredView = view
    dimView.isHidden = true
  }

  /// Draws the veil to `amount` (0 lifts it, 1 draws it fully) over
  /// `duration`, from wherever it is now, even partway through an animation.
  func setAmount(
    _ amount: CGFloat, duration: TimeInterval,
    timing: CAMediaTimingFunctionName = .easeInEaseOut,
    completion: (() -> Void)? = nil
  ) {
    generation += 1
    let generation = generation
    self.amount = amount
    if amount > 0 {
      installFilter()
      dimView.isHidden = false
    }
    let dimLayer = dimView.tint
    guard let blurLayer = blurredView.layer else {
      completion?()
      return
    }
    let fromRadius =
      (blurLayer.presentation() ?? blurLayer).value(forKeyPath: Self.blurKeyPath)
      as? CGFloat ?? 0
    let fromOpacity = (dimLayer.presentation() ?? dimLayer).opacity
    let toRadius = amount * Self.blurRadius
    let toOpacity = Float(amount) * Self.dimOpacity

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.generation == generation else {
          return
        }
        if self.amount == 0 {
          self.removeFilter()
          self.dimView.isHidden = true
        }
        completion?()
      }
    }
    blurLayer.setValue(toRadius, forKeyPath: Self.blurKeyPath)
    dimLayer.opacity = toOpacity
    if duration > 0 {
      let timingFunction = CAMediaTimingFunction(name: timing)
      let blur = CABasicAnimation(keyPath: Self.blurKeyPath)
      blur.fromValue = fromRadius
      blur.toValue = toRadius
      let dim = CABasicAnimation(keyPath: "opacity")
      dim.fromValue = fromOpacity
      dim.toValue = toOpacity
      for (animation, layer) in [(blur, blurLayer), (dim, dimLayer)] {
        animation.duration = duration
        animation.timingFunction = timingFunction
        layer.add(animation, forKey: "veil")
      }
    }
    CATransaction.commit()
  }

  private func installFilter() {
    guard blurredView.contentFilters.isEmpty else {
      return
    }
    // Extends the page's edges outward, so the blur doesn't draw in the
    // transparency past them.
    let clamp = CIFilter(name: "CIAffineClamp")!
    clamp.setValue(NSAffineTransform(), forKey: kCIInputTransformKey)
    clamp.name = "clamp"
    let blur = CIFilter(
      name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 0])!
    blur.name = "blur"
    blurredView.layerUsesCoreImageFilters = true
    blurredView.contentFilters = [clamp, blur]
  }

  private func removeFilter() {
    blurredView.layer?.removeAnimation(forKey: "veil")
    blurredView.contentFilters = []
  }
}

/// The veil's black. It's only drawn: clicks go to whatever the veil is
/// waiting on, over it, or nowhere.
final class VeilDimView: NSView {
  /// The black, in a layer of its own: AppKit keeps the view's own layer's
  /// opacity in step with its alphaValue.
  let tint = CALayer()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    tint.backgroundColor = NSColor.black.cgColor
    tint.opacity = 0
    layer?.addSublayer(tint)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    tint.frame = bounds
    CATransaction.commit()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}
