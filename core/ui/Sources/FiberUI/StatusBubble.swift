import AppKit

/// Shows a hovered link's URL in the window's bottom-left corner.
final class StatusBubble: NSBox {
  private static let padding = NSSize(width: 8, height: 3)

  private let label = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    boxType = .custom
    cornerRadius = 7
    borderWidth = 1
    borderColor = .separatorColor
    fillColor = .windowBackgroundColor
    contentViewMargins = .zero

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.15)
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.shadowBlurRadius = 3
    wantsLayer = true
    self.shadow = shadow

    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingMiddle
    contentView?.addSubview(label)

    alphaValue = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  /// Shows `text`, or hides the bubble if it's empty.
  func setText(_ text: String) {
    if text.isEmpty {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        animator().alphaValue = 0
      }
      return
    }

    label.stringValue = text
    // The content view is inset by the border, so pad by that too.
    let padding = NSSize(
      width: Self.padding.width + borderWidth,
      height: Self.padding.height + borderWidth)
    let labelSize = label.intrinsicContentSize
    let maxWidth = (superview?.bounds.width ?? 0) / 2
    setFrameSize(
      NSSize(
        width: min(labelSize.width.rounded(.up) + 2 * padding.width, maxWidth),
        height: labelSize.height.rounded(.up) + 2 * padding.height))
    if let contentView {
      label.frame = contentView.bounds.insetBy(
        dx: Self.padding.width, dy: Self.padding.height)
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.1
      animator().alphaValue = 1
    }
  }
}
