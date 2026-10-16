import AppKit
import SwiftUI

/// The tab picker's glass as it is this frame: the lip, a capsule centered on
/// the window's top edge, and a body hanging from it like a drop, which grows
/// into the column of tabs. In the picker's coordinates (y grows down).
struct TabPickerDrop: Equatable {
  var lipMinX: CGFloat = 0
  var lipMaxX: CGFloat = 0
  var bodyMidX: CGFloat = 0
  var bodyWidth: CGFloat = 0
  /// How far the body hangs below the lip.
  var depth: CGFloat = 0
  /// How far the middle of the body's bottom edge sags below its corners (up
  /// into the body when negative), at `bulgeX`.
  var bulge: CGFloat = 0
  var bulgeX: CGFloat = 0

  /// The rim shows once the drop is deep enough to hold content.
  private static let rimDepths: ClosedRange<CGFloat> = 12...40
  private static let shadowDepth: CGFloat = 48
  /// As the drop deepens, the lip draws up until its lower edge is just past
  /// the window's, so its round ends go and the column flares out of the edge.
  private static let liftDepths: ClosedRange<CGFloat> = 4...36
  private static let liftClearance: CGFloat = 2

  var bottom: CGFloat { TabPickerModel.lipHeight / 2 + depth }

  var rimWidth: CGFloat {
    TabPickerLayout.rimWidth * Self.progress(depth, through: Self.rimDepths)
  }

  var shadowOpacity: Double {
    Double(Self.progress(depth, through: 0...Self.shadowDepth))
  }

  var shape: TabPickerDropShape {
    let halfHeight = TabPickerModel.lipHeight / 2
    let lift =
      (halfHeight + Self.liftClearance)
      * Self.progress(depth, through: Self.liftDepths)
    let lipMidY = -lift
    // From the lip's lower edge, wherever it is.
    let hang = max(depth + lift, 0)
    let width = max(bodyWidth, 0)
    // The fillets and corners shrink with a shallow drop, so it swells from
    // the lip as a smooth bead.
    let fillet = min(TabPickerLayout.filletRadius, hang / 2)
    let corner = min(TabPickerLayout.cornerRadius, hang - fillet, width / 2)
    return TabPickerDropShape(
      halfHeight: halfHeight, lipMidY: lipMidY, lipMinX: lipMinX,
      lipMaxX: lipMaxX, bodyMinX: bodyMidX - width / 2,
      bodyMaxX: bodyMidX + width / 2, bottom: bottom, bulge: bulge,
      bulgeX: bulgeX, filletRadius: fillet, cornerRadius: corner)
  }

  private static func progress(
    _ value: CGFloat, through range: ClosedRange<CGFloat>
  ) -> CGFloat {
    let span = range.upperBound - range.lowerBound
    return min(max((value - range.lowerBound) / span, 0), 1)
  }
}

/// The lip, and the body hanging from it, joined by concave fillets so the
/// glass flows out of the window's edge.
struct TabPickerDropShape: InsettableShape {
  var halfHeight: CGFloat
  /// The lip's centerline: the window's edge at rest, above it once open.
  var lipMidY: CGFloat
  var lipMinX: CGFloat
  var lipMaxX: CGFloat
  var bodyMinX: CGFloat
  var bodyMaxX: CGFloat
  var bottom: CGFloat
  var bulge: CGFloat
  var bulgeX: CGFloat
  var filletRadius: CGFloat
  var cornerRadius: CGFloat

  /// A quarter circle's control points are this far along its tangents, in
  /// radii.
  private static let kappa: CGFloat = 0.5523
  /// The sag's control points, as shares of each half of the bottom edge:
  /// from the corner, and from the deepest point.
  private static let sagEase: CGFloat = 0.15
  private static let sagRound: CGFloat = 0.6

  /// Offsetting every edge inward keeps the fillets' centers where they were,
  /// so the inset shape stays concentric with this one.
  func inset(by amount: CGFloat) -> TabPickerDropShape {
    var shape = self
    shape.halfHeight = max(halfHeight - amount, 0)
    shape.lipMinX += amount
    shape.lipMaxX -= amount
    shape.bodyMinX += amount
    shape.bodyMaxX -= amount
    shape.bottom -= amount
    shape.filletRadius += amount
    shape.cornerRadius = max(cornerRadius - amount, 0)
    return shape
  }

  func path(in rect: CGRect) -> Path {
    let h = halfHeight
    let k = Self.kappa
    let top = lipMidY - h
    let mid = lipMidY
    let base = lipMidY + h
    let left = bodyMinX
    let right = max(bodyMaxX, bodyMinX)
    let hang = max(bottom - base, 0)
    let r = min(max(cornerRadius, 0), (right - left) / 2, hang)
    let f = min(max(filletRadius, 0), hang - r)
    let bottom = base + hang
    // The lip's round ends stay clear of the fillets.
    let lipMin = min(lipMinX, left - f - h)
    let lipMax = max(lipMaxX, right + f + h)
    let sagX = min(max(bulgeX, left + r), right - r)

    var path = Path()
    path.move(to: CGPoint(x: lipMin + h, y: top))
    path.addCurve(
      to: CGPoint(x: lipMin, y: mid),
      control1: CGPoint(x: lipMin + h - k * h, y: top),
      control2: CGPoint(x: lipMin, y: mid - k * h))
    path.addCurve(
      to: CGPoint(x: lipMin + h, y: base),
      control1: CGPoint(x: lipMin, y: mid + k * h),
      control2: CGPoint(x: lipMin + h - k * h, y: base))
    path.addLine(to: CGPoint(x: left - f, y: base))
    path.addCurve(
      to: CGPoint(x: left, y: base + f),
      control1: CGPoint(x: left - f + k * f, y: base),
      control2: CGPoint(x: left, y: base + f - k * f))
    path.addLine(to: CGPoint(x: left, y: bottom - r))
    path.addCurve(
      to: CGPoint(x: left + r, y: bottom),
      control1: CGPoint(x: left, y: bottom - r + k * r),
      control2: CGPoint(x: left + r - k * r, y: bottom))
    // The bottom edge sags in two halves that meet level at `sagX`, leaving
    // the corners level so it stays smooth into them, but soon, so it's
    // round like a drop's rather than a bump.
    let leftRun = sagX - left - r
    let rightRun = right - r - sagX
    path.addCurve(
      to: CGPoint(x: sagX, y: bottom + bulge),
      control1: CGPoint(x: left + r + Self.sagEase * leftRun, y: bottom),
      control2: CGPoint(
        x: sagX - Self.sagRound * leftRun, y: bottom + bulge))
    path.addCurve(
      to: CGPoint(x: right - r, y: bottom),
      control1: CGPoint(
        x: sagX + Self.sagRound * rightRun, y: bottom + bulge),
      control2: CGPoint(x: right - r - Self.sagEase * rightRun, y: bottom))
    path.addCurve(
      to: CGPoint(x: right, y: bottom - r),
      control1: CGPoint(x: right - r + k * r, y: bottom),
      control2: CGPoint(x: right, y: bottom - r + k * r))
    path.addLine(to: CGPoint(x: right, y: base + f))
    path.addCurve(
      to: CGPoint(x: right + f, y: base),
      control1: CGPoint(x: right, y: base + f - k * f),
      control2: CGPoint(x: right + f - k * f, y: base))
    path.addLine(to: CGPoint(x: lipMax - h, y: base))
    path.addCurve(
      to: CGPoint(x: lipMax, y: mid),
      control1: CGPoint(x: lipMax - h + k * h, y: base),
      control2: CGPoint(x: lipMax, y: mid + k * h))
    path.addCurve(
      to: CGPoint(x: lipMax - h, y: top),
      control1: CGPoint(x: lipMax, y: mid - k * h),
      control2: CGPoint(x: lipMax - h + k * h, y: top))
    path.closeSubpath()
    return path
  }
}

/// Moves the drop toward where the picker wants it, each part on a spring of
/// its own, so it pours, gathers and wobbles rather than tweening.
struct TabPickerDropMotion {
  struct Target: Equatable {
    var lipMinX: CGFloat
    var lipMaxX: CGFloat
    var bodyMidX: CGFloat
    var bodyWidth: CGFloat
    var depth: CGFloat
    /// The bottom edge's sag at rest, before what pouring adds.
    var swell: CGFloat = 0
    var bulgeX: CGFloat
  }

  private struct Spring {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat

    init(_ value: CGFloat) {
      self.value = value
      target = value
    }

    /// `response` is roughly the time to settle, as SwiftUI's springs take it.
    mutating func step(
      _ dt: CGFloat, response: CGFloat, dampingRatio: CGFloat
    ) {
      let stiffness = pow(2 * .pi / response, 2)
      let damping = 4 * .pi * dampingRatio / response
      velocity += (-stiffness * (value - target) - damping * velocity) * dt
      value += velocity * dt
    }

    var isSettled: Bool {
      abs(value - target) < 0.05 && abs(velocity) < 1
    }

    mutating func snap() {
      value = target
      velocity = 0
    }
  }

  /// Sag for each point a second the body pours downward, and the most it
  /// sags either way.
  private static let sagPerSpeed: CGFloat = 0.018
  private static let sagRange: ClosedRange<CGFloat> = -3...12
  /// The longest step the springs take at once, for stability.
  private static let maxStep: CGFloat = 1 / 240

  private var lipMinX: Spring
  private var lipMaxX: Spring
  private var bodyMidX: Spring
  private var bodyWidth: Spring
  private var depth: Spring
  private var bulge = Spring(0)
  private var bulgeX: Spring
  private var swell: CGFloat = 0

  init(at target: Target) {
    lipMinX = Spring(target.lipMinX)
    lipMaxX = Spring(target.lipMaxX)
    bodyMidX = Spring(target.bodyMidX)
    bodyWidth = Spring(target.bodyWidth)
    depth = Spring(target.depth)
    bulgeX = Spring(target.bulgeX)
    swell = target.swell
    bulge = Spring(target.swell)
  }

  var drop: TabPickerDrop {
    TabPickerDrop(
      lipMinX: lipMinX.value, lipMaxX: lipMaxX.value,
      bodyMidX: bodyMidX.value, bodyWidth: bodyWidth.value,
      depth: depth.value, bulge: bulge.value, bulgeX: bulgeX.value)
  }

  var target: Target {
    get {
      Target(
        lipMinX: lipMinX.target, lipMaxX: lipMaxX.target,
        bodyMidX: bodyMidX.target, bodyWidth: bodyWidth.target,
        depth: depth.target, swell: swell, bulgeX: bulgeX.target)
    }
    set {
      lipMinX.target = newValue.lipMinX
      lipMaxX.target = newValue.lipMaxX
      bodyMidX.target = newValue.bodyMidX
      bodyWidth.target = newValue.bodyWidth
      depth.target = newValue.depth
      swell = newValue.swell
      bulgeX.target = newValue.bulgeX
    }
  }

  var isSettled: Bool {
    [lipMinX, lipMaxX, bodyMidX, bodyWidth, depth, bulge, bulgeX].allSatisfy(
      \.isSettled)
  }

  /// Jumps to the target, for when the window resizes with nothing moving.
  mutating func snap() {
    for keyPath in [
      \Self.lipMinX, \.lipMaxX, \.bodyMidX, \.bodyWidth, \.depth, \.bulgeX,
    ] {
      self[keyPath: keyPath].snap()
    }
    bulge.target = swell
    bulge.snap()
  }

  /// Advances `elapsed` seconds. With Reduce Motion, nothing overshoots or
  /// sags.
  mutating func step(_ elapsed: CGFloat, reduceMotion: Bool) {
    var remaining = min(elapsed, 0.1)
    while remaining > 0 {
      let dt = min(remaining, Self.maxStep)
      remaining -= dt
      advance(dt, reduceMotion: reduceMotion)
    }
  }

  private mutating func advance(_ dt: CGFloat, reduceMotion: Bool) {
    func damping(_ ratio: CGFloat) -> CGFloat {
      reduceMotion ? 1 : ratio
    }
    // Pouring down overshoots a little and settles; drawing back up into the
    // lip is quicker, and doesn't.
    let isPouring = depth.target >= depth.value
    depth.step(
      dt, response: isPouring ? 0.46 : 0.34,
      dampingRatio: damping(isPouring ? 0.64 : 0.92))
    bodyWidth.step(dt, response: 0.5, dampingRatio: damping(0.68))
    bodyMidX.step(dt, response: 0.42, dampingRatio: damping(0.86))
    lipMinX.step(dt, response: 0.5, dampingRatio: damping(0.8))
    lipMaxX.step(dt, response: 0.5, dampingRatio: damping(0.8))
    bulgeX.step(dt, response: 0.3, dampingRatio: 1)
    // The leading edge rounds out as it pours, then wobbles flat.
    bulge.target =
      reduceMotion
      ? 0
      : min(
        max(swell + depth.velocity * Self.sagPerSpeed, Self.sagRange.lowerBound),
        Self.sagRange.upperBound)
    bulge.step(dt, response: 0.24, dampingRatio: damping(0.42))
  }
}
