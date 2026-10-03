import AppKit

/// Blurs a window's page and darkens the window while it waits on the user.
/// The blur is a filter on the page's views: a backdrop only samples inside
/// the window, so its blur would darken toward the window's edges.
@MainActor
final class Veil {
  /// A fully drawn veil's blur radius.
  private static let blurRadius: CGFloat = 24
  /// Its prompts' white text needs a white page no lighter than a mid gray.
  private static let dimming = Dimming(drop: 57, maxOpacity: 0.7)
  private static let blurKeyPath = "filters.blur.inputRadius"
  /// How long the black takes to follow a new measure of the page.
  private static let relightDuration: TimeInterval = 0.2

  /// Darkens the window. Its owner puts it over the page and the controls.
  let dimView = DimView()
  /// The opacity of a fully drawn veil's black (see setPageLightness(_:)).
  private var dimOpacity = Float(dimming.opacity(forPageLightness: 100))
  /// How far the veil is drawn, from 0 (lifted) to 1, once any animation
  /// ends.
  private(set) var amount: CGFloat = 0
  private let blurredView: NSView
  /// Counts changes to `amount`, so a lift that finishes after the veil was
  /// drawn again leaves the filter on.
  private var generation = 0

  /// Blurs `view` (the page and DevTools) when drawn.
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
    guard let blurLayer = blurredView.layer else {
      completion?()
      return
    }
    let fromRadius =
      (blurLayer.presentation() ?? blurLayer).value(forKeyPath: Self.blurKeyPath)
      as? CGFloat ?? 0
    let toRadius = amount * Self.blurRadius

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
    if duration > 0 {
      let blur = CABasicAnimation(keyPath: Self.blurKeyPath)
      blur.fromValue = fromRadius
      blur.toValue = toRadius
      blur.duration = duration
      blur.timingFunction = CAMediaTimingFunction(name: timing)
      blurLayer.add(blur, forKey: "veil")
    }
    dimView.setOpacity(
      Float(amount) * dimOpacity, duration: duration, timing: timing)
    CATransaction.commit()
  }

  /// Darkens the veil so that it dims a page whose mean L* is `lightness` by
  /// about as much as any other (see Dimming).
  func setPageLightness(_ lightness: Double) {
    dimOpacity = Float(Self.dimming.opacity(forPageLightness: lightness))
    if amount > 0 {
      dimView.setOpacity(
        Float(amount) * dimOpacity, duration: Self.relightDuration)
    }
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

  /// The filter costs an offscreen pass over the page every frame, so it's
  /// only on while the veil is.
  private func removeFilter() {
    blurredView.layer?.removeAnimation(forKey: "veil")
    blurredView.contentFilters = []
  }
}
