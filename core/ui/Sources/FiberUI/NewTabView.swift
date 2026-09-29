import AppKit

/// Fiber's New Tab page (chrome://newtab), drawn over the tab's page, which is
/// empty and the same color. The omnibar opens over it; clicking the page
/// opens it again.
final class NewTabView: NSView {
  private static let markWidth: CGFloat = 132

  var onClick: () -> Void = {}

  override init(frame: NSRect) {
    super.init(frame: frame)
    let mark = NSImageView(image: FiberMark.image)
    mark.imageScaling = .scaleProportionallyUpOrDown
    mark.contentTintColor = .quaternaryLabelColor
    mark.translatesAutoresizingMaskIntoConstraints = false
    addSubview(mark)
    let size = FiberMark.image.size
    NSLayoutConstraint.activate([
      mark.centerXAnchor.constraint(equalTo: centerXAnchor),
      mark.centerYAnchor.constraint(equalTo: centerYAnchor),
      mark.widthAnchor.constraint(equalToConstant: Self.markWidth),
      mark.heightAnchor.constraint(
        equalTo: mark.widthAnchor, multiplier: size.height / size.width),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // Like the page it stands in for, it doesn't move the window.
  override var mouseDownCanMoveWindow: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    super.hitTest(point) == nil ? nil : self
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }

  override func mouseDown(with event: NSEvent) {
    onClick()
  }
}
