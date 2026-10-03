import AppKit
import SwiftUI

/// How the tab overlay's pins, address, extensions and panel come and go: in a
/// wave that spreads from the panel's top-left corner as it opens, played
/// back, quicker, as it closes. The pins, address and extensions move a few
/// points, down into place and back up, or from the left and back beside the
/// panel, fading in as they arrive and out once they've lifted. The panel is
/// dimmer past where the wave has reached.
@MainActor
enum TabOverlayMotion {
  /// How far the pins move, and the address and extensions above them.
  static let travel: CGFloat = 6
  /// How far the address and extensions move beside the panel.
  static let sideTravel: CGFloat = 9
  /// How fast the wave spreads as the overlay opens, in points a second:
  /// beside the panel, slow enough for the address and extensions stacked
  /// there to come one after the other, and across it.
  private static let speed: CGFloat = 700
  private static let panelSpeed: CGFloat = 4200
  /// How long the wave takes across the pins: `pinsBaseDuration`, and
  /// `pinStepDuration` more for each pin it passes, so longer the more there
  /// are, though less from each to the next.
  private static let pinsBaseDuration: TimeInterval = 0.15
  private static let pinStepDuration: TimeInterval = 0.0145
  private static let openDuration: TimeInterval = 0.3
  /// How long closing takes, for each second opening does.
  private static let closeShare = 0.5
  /// The panel's soft edge, behind the wave's front.
  static let panelEdgeWidth: CGFloat = 240
  /// How much of the panel shows past the wave's front.
  static let panelFloorOpacity = 0.75
  private static let curve = (0.2, 0.8, 0.2, 1.0)
  /// As it closes, what moves lifts with `liftCurve`, and fades out with
  /// `fadeOutCurve` only from `fadeOutStart` of the way through the lift, so
  /// the lift shows.
  private static let liftCurve = (0.42, 0.0, 0.58, 1.0)
  private static let fadeOutCurve = (0.42, 0.0, 1.0, 1.0)
  private static let fadeOutStart = 0.3
  private static let moveKey = "tabOverlayMotion.move"
  private static let fadeKey = "tabOverlayMotion.fade"

  /// How long after the overlay starts to open something beside the panel,
  /// `distance` points from its corner, starts to move.
  static func delay(at distance: CGFloat) -> TimeInterval {
    distance / speed
  }

  /// The same for something above the panel, as the panel's wave reaches it.
  static func panelDelay(at distance: CGFloat) -> TimeInterval {
    distance / panelSpeed
  }

  /// How long the wave takes from the nearest pin to the farthest, `reach`
  /// beyond it.
  static func pinsDuration(reach: CGFloat) -> TimeInterval {
    guard reach > 0 else {
      return 0
    }
    return pinsBaseDuration + pinStepDuration * reach / PinGridLayout.step
  }

  /// How long opening takes, with the last thing to move starting
  /// `lastDelay` in, over a panel the wave runs `panelReach` across.
  static func span(lastDelay: TimeInterval, panelReach: CGFloat)
    -> TimeInterval
  {
    max(
      lastDelay + openDuration, panelDuration(reach: panelReach),
      PaletteView.fadeInDuration)
  }

  /// How long after the overlay starts to close it fades out, as the last of
  /// what's on it leaves, for an opening `span` long.
  static func fadeOutDelay(span: TimeInterval) -> TimeInterval {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? 0 : max(closeShare * span - PaletteView.fadeOutDuration, 0)
  }

  /// For the wave across the panel, which runs `reach`.
  static func panelAnimation(
    reach: CGFloat, span: TimeInterval, isOpening: Bool
  ) -> Animation {
    let timing = timing(
      delay: 0, duration: panelDuration(reach: reach), span: span,
      isOpening: isOpening)
    return .linear(duration: timing.duration).delay(timing.delay)
  }

  /// `reach`, and the panel's soft edge beyond, as the overlay opens.
  private static func panelDuration(reach: CGFloat) -> TimeInterval {
    (reach + panelEdgeWidth) / panelSpeed
  }

  enum Property {
    case offset, opacity
  }

  /// For the `property` of something that starts to move `delay` into an
  /// opening `span` long.
  static func animation(
    _ property: Property, delay: TimeInterval, span: TimeInterval,
    isOpening: Bool
  ) -> Animation {
    let timing = timing(
      of: property, delay: delay, span: span, isOpening: isOpening)
    let curve = timing.curve
    return .timingCurve(
      curve.0, curve.1, curve.2, curve.3, duration: timing.duration
    ).delay(timing.delay)
  }

  /// Moves `view` in from `offset` (y growing down) or out to it, from
  /// wherever it is now, as SwiftUI views do with
  /// `animation(_:delay:span:isOpening:)`.
  static func move(
    _ view: NSView, from offset: CGSize, isOpening: Bool, delay: TimeInterval,
    span: TimeInterval
  ) {
    guard let layer = view.layer else {
      return
    }
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      layer.removeAnimation(forKey: moveKey)
      layer.removeAnimation(forKey: fadeKey)
      return
    }
    let isFlipped = layer.superlayer?.contentsAreFlipped() ?? false
    let away = CGSize(
      width: offset.width, height: isFlipped ? offset.height : -offset.height)
    // Before it first opens, it hasn't been moved out yet.
    let presentation =
      isOpening && layer.animation(forKey: moveKey) == nil
      ? nil : layer.presentation()
    let fromOffset =
      (presentation?.value(forKeyPath: "transform.translation") as? NSValue)?
      .sizeValue ?? (isOpening ? away : .zero)
    let fromOpacity = presentation?.opacity ?? (isOpening ? 0 : 1)

    let move = CABasicAnimation(keyPath: "transform.translation")
    move.isAdditive = true
    move.fromValue = NSValue(size: fromOffset)
    move.toValue = NSValue(size: isOpening ? .zero : away)
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = fromOpacity
    fade.toValue = isOpening ? 1 : 0
    let now = layer.convertTime(CACurrentMediaTime(), from: nil)
    for (animation, key, property) in [
      (move, moveKey, Property.offset), (fade, fadeKey, .opacity),
    ] {
      let timing = timing(
        of: property, delay: delay, span: span, isOpening: isOpening)
      let curve = timing.curve
      animation.beginTime = now + timing.delay
      animation.duration = timing.duration
      animation.timingFunction = CAMediaTimingFunction(
        controlPoints: Float(curve.0), Float(curve.1), Float(curve.2),
        Float(curve.3))
      animation.fillMode = .both
      // Out of sight until it opens again.
      animation.isRemovedOnCompletion = isOpening
      layer.add(animation, forKey: key)
    }
  }

  /// Something that moves `duration` long, `delay` into an opening `span`
  /// long, as it opens, or played back as it closes.
  private static func timing(
    delay: TimeInterval, duration: TimeInterval, span: TimeInterval,
    isOpening: Bool
  ) -> (delay: TimeInterval, duration: TimeInterval) {
    isOpening
      ? (delay, duration)
      : (
        closeShare * max(span - delay - duration, 0), closeShare * duration
      )
  }

  private static func timing(
    of property: Property, delay: TimeInterval, span: TimeInterval,
    isOpening: Bool
  ) -> (
    delay: TimeInterval, duration: TimeInterval,
    curve: (Double, Double, Double, Double)
  ) {
    let timing = timing(
      delay: delay, duration: openDuration, span: span, isOpening: isOpening)
    switch (isOpening, property) {
    case (true, _):
      return (timing.delay, timing.duration, curve)
    case (false, .offset):
      return (timing.delay, timing.duration, liftCurve)
    case (false, .opacity):
      return (
        timing.delay + fadeOutStart * timing.duration,
        (1 - fadeOutStart) * timing.duration, fadeOutCurve
      )
    }
  }
}
