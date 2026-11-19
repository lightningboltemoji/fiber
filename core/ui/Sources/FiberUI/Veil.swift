import AppKit

/// Blurs a window's page and darkens the window while it waits on the user.
@MainActor
final class Veil {
  /// A fully drawn veil's blur radius, and the opacity of its black.
  private static let blurRadius: CGFloat = 24
  private static let dimOpacity: Float = 0.6

  /// Darkens the window. Its owner puts it over the page and the controls.
  let dimView = DimView()
  /// How far the veil is drawn, from 0 (lifted) to 1, once any animation
  /// ends.
  private(set) var amount: CGFloat = 0
  private let blur: ViewBlur

  /// Blurs `view` (the page and DevTools) when drawn.
  init(blurring view: NSView) {
    blur = ViewBlur(view)
    dimView.isHidden = true
  }

  /// Draws the veil to `amount` (0 lifts it, 1 draws it fully) over
  /// `duration`, from wherever it is now, even partway through an animation.
  func setAmount(
    _ amount: CGFloat, duration: TimeInterval,
    timing: CAMediaTimingFunctionName = .easeInEaseOut,
    completion: (() -> Void)? = nil
  ) {
    self.amount = amount
    if amount > 0 {
      dimView.isHidden = false
    }
    blur.setRadius(amount * Self.blurRadius, duration: duration, timing: timing)
    { [weak self] in
      if self?.amount == 0 {
        self?.dimView.isHidden = true
      }
      completion?()
    }
    dimView.setOpacity(
      Float(amount) * Self.dimOpacity, duration: duration, timing: timing)
  }
}

/// Blurs a view and its subviews with a filter on the view: a backdrop only
/// samples inside the window, so its blur would darken toward the window's
/// edges.
@MainActor
final class ViewBlur {
  private static let radiusKeyPath = "filters.blur.inputRadius"

  private let view: NSView
  /// Counts changes to the radius, so a blur taken off after it was put back
  /// leaves the filter on.
  private var generation = 0
  private var radius: CGFloat = 0

  init(_ view: NSView) {
    self.view = view
  }

  /// Takes the blur to `radius` over `duration`, from wherever it is now, even
  /// partway through an animation, then calls `completion` unless it's been
  /// changed again since.
  func setRadius(
    _ radius: CGFloat, duration: TimeInterval,
    timing: CAMediaTimingFunctionName = .easeInEaseOut,
    completion: (() -> Void)? = nil
  ) {
    generation += 1
    let generation = generation
    self.radius = radius
    if radius > 0 {
      installFilter()
    }
    guard let layer = view.layer, !view.contentFilters.isEmpty else {
      completion?()
      return
    }
    let fromRadius =
      (layer.presentation() ?? layer).value(forKeyPath: Self.radiusKeyPath)
      as? CGFloat ?? 0
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.generation == generation else {
          return
        }
        if self.radius == 0 {
          self.removeFilter()
        }
        completion?()
      }
    }
    layer.setValue(radius, forKeyPath: Self.radiusKeyPath)
    if duration > 0 {
      let animation = CABasicAnimation(keyPath: Self.radiusKeyPath)
      animation.fromValue = fromRadius
      animation.toValue = radius
      animation.duration = duration
      animation.timingFunction = CAMediaTimingFunction(name: timing)
      layer.add(animation, forKey: "blur")
    }
    CATransaction.commit()
  }

  private func installFilter() {
    guard view.contentFilters.isEmpty else {
      return
    }
    // Extends the view's edges outward, so the blur doesn't draw in the
    // transparency past them.
    let clamp = CIFilter(name: "CIAffineClamp")!
    clamp.setValue(NSAffineTransform(), forKey: kCIInputTransformKey)
    clamp.name = "clamp"
    let blur = CIFilter(
      name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 0])!
    blur.name = "blur"
    view.layerUsesCoreImageFilters = true
    view.contentFilters = [clamp, blur]
  }

  /// The filter costs an offscreen pass over the view every frame, so it's
  /// only on while there's a blur.
  private func removeFilter() {
    view.layer?.removeAnimation(forKey: "blur")
    view.contentFilters = []
  }
}
