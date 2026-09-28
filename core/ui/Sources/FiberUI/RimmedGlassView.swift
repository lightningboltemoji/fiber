import AppKit
import SwiftUI

/// Liquid Glass with a pronounced rim, like Safari's address field: a second
/// layer of glass inset inside the first, so each draws its edge and the band
/// between them reads as a thick border. Content goes in the inner glass.
final class RimmedGlassView: NSView {
  /// The corner radius of the outer glass. The inner glass's corners are
  /// concentric with it.
  var cornerRadius: CGFloat = 0 {
    didSet { updateCornerRadii() }
  }

  /// The view shown in the inner glass, sized to fill it.
  var contentView: NSView? {
    get { inner.contentView }
    set { inner.contentView = newValue }
  }

  private let rimWidth: CGFloat
  private let outer = NSGlassEffectView()
  private let rimHolder = NSView()
  private let inner = NSGlassEffectView()

  init(rimWidth: CGFloat) {
    self.rimWidth = rimWidth
    super.init(frame: .zero)
    rimHolder.addSubview(inner)
    outer.contentView = rimHolder
    addSubview(outer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    outer.frame = bounds
    rimHolder.frame = outer.bounds
    // insetBy(dx:dy:) returns .null for a rect smaller than the rim.
    let innerFrame = rimHolder.bounds.insetBy(dx: rimWidth, dy: rimWidth)
    inner.frame = innerFrame.isNull ? .zero : innerFrame
  }

  private func updateCornerRadii() {
    outer.cornerRadius = cornerRadius
    inner.cornerRadius = max(cornerRadius - rimWidth, 0)
  }
}

/// RimmedGlassView in SwiftUI, for glass whose shape animates.
struct RimmedGlass: View {
  let cornerRadius: CGFloat
  let rimWidth: CGFloat

  var body: some View {
    Color.clear
      .glassEffect(
        .regular,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay {
        Color.clear
          .glassEffect(
            .regular,
            in: RoundedRectangle(
              cornerRadius: max(cornerRadius - rimWidth, 0),
              style: .continuous)
          )
          .padding(rimWidth)
      }
  }
}
