import AppKit
import FiberBridge

/// What the window shows in place of a page whose renderer is gone (see
/// FiberSadTab), over the page, which is empty.
final class SadTabView: NSView {
  private static let textWidth: CGFloat = 420

  var onButton: () -> Void = {}
  var onHelp: () -> Void = {}

  private let stack = NSStackView()
  private var shown: FiberSadTab?

  init() {
    super.init(frame: .zero)
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -64),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func show(_ sadTab: FiberSadTab) {
    // Page state comes often; the sad tab rarely changes.
    if let shown, shown.title == sadTab.title, shown.message == sadTab.message,
      shown.suggestions == sadTab.suggestions,
      shown.errorCode == sadTab.errorCode,
      shown.buttonTitle == sadTab.buttonTitle, shown.helpTitle == sadTab.helpTitle
    {
      return
    }
    shown = sadTab
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

    let symbol = NSImageView(
      image: NSImage(
        systemSymbolName: "exclamationmark.triangle",
        accessibilityDescription: nil)!)
    symbol.symbolConfiguration = .init(pointSize: 44, weight: .light)
    symbol.contentTintColor = .tertiaryLabelColor
    stack.addArrangedSubview(symbol)
    stack.setCustomSpacing(16, after: symbol)

    let title = NSTextField(wrappingLabelWithString: sadTab.title)
    title.font = .systemFont(ofSize: 22, weight: .semibold)
    title.alignment = .center
    title.isSelectable = false
    stack.addArrangedSubview(title)

    stack.addArrangedSubview(Self.makeText(sadTab.message))
    for suggestion in sadTab.suggestions {
      stack.addArrangedSubview(Self.makeText("• " + suggestion))
    }

    let errorCode = NSTextField(labelWithString: sadTab.errorCode)
    errorCode.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    errorCode.textColor = .tertiaryLabelColor
    // Selectable, to copy it into a bug report.
    errorCode.isSelectable = true
    stack.addArrangedSubview(errorCode)
    stack.setCustomSpacing(20, after: errorCode)

    let button = NSButton(
      title: sadTab.buttonTitle, target: self, action: #selector(buttonPressed))
    button.bezelStyle = .glass
    button.borderShape = .capsule
    button.controlSize = .large
    button.tintProminence = .primary
    button.keyEquivalent = "\r"
    let help = NSButton(
      title: sadTab.helpTitle, target: self, action: #selector(helpPressed))
    help.isBordered = false
    help.contentTintColor = .linkColor
    let buttons = NSStackView(views: [help, button])
    buttons.orientation = .horizontal
    buttons.spacing = 16
    stack.addArrangedSubview(buttons)
  }

  private static func makeText(_ string: String) -> NSTextField {
    let text = NSTextField(wrappingLabelWithString: string)
    text.alignment = .center
    text.isSelectable = false
    text.textColor = .secondaryLabelColor
    text.preferredMaxLayoutWidth = textWidth
    return text
  }

  @objc private func buttonPressed() {
    onButton()
  }

  @objc private func helpPressed() {
    onHelp()
  }

  // Like the page it stands in for, it doesn't move the window.
  override var mouseDownCanMoveWindow: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }
}
