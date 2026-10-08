import AppKit

/// Fiber's New Tab page (chrome://newtab), drawn over the tab's page, which is
/// empty and the same color. The omnibar opens over it; clicking the page
/// opens it again. An Incognito window's says what Incognito keeps.
final class NewTabView: NSView {
  private static let markWidth: CGFloat = 112
  private static let incognitoTextWidth: CGFloat = 340

  var onClick: () -> Void = {}

  init(isIncognito: Bool) {
    super.init(frame: .zero)
    let content = isIncognito ? Self.makeIncognitoContent() : Self.makeMark()
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    NSLayoutConstraint.activate([
      content.centerXAnchor.constraint(equalTo: centerXAnchor),
      content.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  private static func makeMark() -> NSView {
    let mark = NSImageView(image: FiberMark.image)
    mark.imageScaling = .scaleProportionallyUpOrDown
    mark.contentTintColor = .quaternaryLabelColor
    let size = FiberMark.image.size
    NSLayoutConstraint.activate([
      mark.widthAnchor.constraint(equalToConstant: markWidth),
      mark.heightAnchor.constraint(
        equalTo: mark.widthAnchor, multiplier: size.height / size.width),
    ])
    return mark
  }

  private static func makeIncognitoContent() -> NSView {
    let symbol = NSImageView(
      image: NSImage(
        systemSymbolName: "mustache", accessibilityDescription: nil)!)
    symbol.symbolConfiguration = .init(pointSize: 44, weight: .light)
    symbol.contentTintColor = .tertiaryLabelColor

    let title = NSTextField(labelWithString: "Incognito")
    title.font = .systemFont(ofSize: 22, weight: .semibold)
    title.textColor = .secondaryLabelColor

    let explanation = NSTextField(
      wrappingLabelWithString:
        "Fiber won't keep your history, cookies or site data. "
        + "Sites and your network can still see what you do.")
    explanation.alignment = .center
    explanation.isSelectable = false
    explanation.textColor = .secondaryLabelColor
    explanation.preferredMaxLayoutWidth = incognitoTextWidth

    let stack = NSStackView(views: [symbol, title, explanation])
    stack.orientation = .vertical
    stack.spacing = 8
    stack.setCustomSpacing(16, after: symbol)
    return stack
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
