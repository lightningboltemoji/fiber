import AppKit

/// A shadow around a rounded rect the size of its bounds, like a window's:
/// subtle, and a little heavier below. The shadow is masked off inside the
/// rect, so it doesn't darken the translucent glass laid over it.
final class OutsetShadowView: NSView {
  private static let radius: CGFloat = 16
  private static let offset = CGSize(width: 0, height: -4)
  private static let opacity: CGFloat = 0.2

  var cornerRadius: CGFloat = 0 {
    didSet { needsLayout = true }
  }
  private let mask = CAShapeLayer()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    // Set on the view: AppKit overwrites the layer's shadow properties with
    // the view's `shadow`. The layer only gets the shape to cast it from.
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(Self.opacity)
    shadow.shadowBlurRadius = Self.radius
    shadow.shadowOffset = Self.offset
    self.shadow = shadow
    mask.fillRule = .evenOdd
    layer?.mask = mask
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let shape = CGPath(
      roundedRect: bounds, cornerWidth: cornerRadius,
      cornerHeight: cornerRadius, transform: nil)
    // Everything the shadow can reach, minus the shape itself.
    let reach = 2 * Self.radius + abs(Self.offset.height)
    let outside = CGMutablePath()
    outside.addRect(bounds.insetBy(dx: -reach, dy: -reach))
    outside.addPath(shape)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.shadowPath = shape
    mask.frame = layer?.bounds ?? bounds
    mask.path = outside
    CATransaction.commit()
  }
}
