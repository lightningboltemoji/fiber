import AppKit

/// What a window waits on the user for, shown over its veil (see
/// BrowserWindowController.present(_:)): a title, a message, anything else in
/// between, and a row of glass buttons, centered over the page. Return presses
/// the default button and Escape the cancel button.
///
/// While it's up, the window is the prompt's: it covers the window's content,
/// taking its clicks and scrolls, holds keyboard focus, and swallows the menu's
/// shortcuts, as a modal alert would.
@MainActor
final class VeilPrompt: NSView {
  struct Button {
    enum Role {
      /// Return presses it; it's tinted.
      case `default`
      /// Escape presses it.
      case cancel
      case other
    }

    var title: String
    var role: Role
    var action: () -> Void
  }

  private enum Metrics {
    static let maxWidth: CGFloat = 480
    static let sideMargin: CGFloat = 32
    static let eyebrowSpacing: CGFloat = 6
    static let titleSpacing: CGFloat = 8
    static let accessorySpacing: CGFloat = 20
    static let buttonsSpacing: CGFloat = 28
    static let buttonSpacing: CGFloat = 12
    static let buttonMinWidth: CGFloat = 120
    static let titleSize: CGFloat = 28
    static let messageSize: CGFloat = 15
    static let eyebrowSize: CGFloat = 13
  }

  /// The line under the title.
  var message: String {
    get { messageLabel.stringValue }
    set { messageLabel.stringValue = newValue }
  }

  private let stack = NSStackView()
  private let messageLabel: NSTextField
  private let buttonsRow = NSStackView()
  private var buttons: [(NSButton, Button)] = []

  /// `eyebrow` goes over the title, smaller (the site asking, say).
  /// `accessory` goes between the message and the buttons.
  init(
    eyebrow: String? = nil, title: String, message: String,
    accessory: NSView? = nil, buttons: [Button]
  ) {
    messageLabel = Self.makeLabel(
      message, font: .systemFont(ofSize: Metrics.messageSize),
      color: .white.withAlphaComponent(0.8))
    super.init(frame: .zero)
    // Dark glass, and white text brighter than the system's secondary colors:
    // over a white page, the veil is only a mid gray.
    appearance = NSAppearance(named: .darkAqua)

    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    if let eyebrow, !eyebrow.isEmpty {
      let label = Self.makeLabel(
        eyebrow, font: .systemFont(ofSize: Metrics.eyebrowSize, weight: .medium),
        color: .white.withAlphaComponent(0.65))
      stack.addArrangedSubview(label)
      stack.setCustomSpacing(Metrics.eyebrowSpacing, after: label)
    }
    let titleLabel = Self.makeLabel(
      title, font: .systemFont(ofSize: Metrics.titleSize, weight: .semibold),
      color: .white)
    stack.addArrangedSubview(titleLabel)
    stack.setCustomSpacing(Metrics.titleSpacing, after: titleLabel)
    stack.addArrangedSubview(messageLabel)
    var last: NSView = messageLabel
    if let accessory {
      stack.setCustomSpacing(Metrics.accessorySpacing, after: last)
      stack.addArrangedSubview(accessory)
      last = accessory
    }
    stack.setCustomSpacing(Metrics.buttonsSpacing, after: last)

    buttonsRow.orientation = .horizontal
    buttonsRow.spacing = Metrics.buttonSpacing
    for spec in buttons {
      let button = Self.makeButton(spec)
      button.target = self
      button.action = #selector(buttonPressed(_:))
      buttonsRow.addArrangedSubview(button)
      self.buttons.append((button, spec))
    }
    stack.addArrangedSubview(buttonsRow)

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.widthAnchor.constraint(
        lessThanOrEqualTo: widthAnchor, constant: -2 * Metrics.sideMargin),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.maxWidth),
      titleLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
      messageLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
    ])

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(title)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // MARK: Buttons

  private static func makeLabel(_ text: String, font: NSFont, color: NSColor)
    -> NSTextField
  {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = font
    label.textColor = color
    label.alignment = .center
    label.isSelectable = false
    return label
  }

  private static func makeButton(_ spec: Button) -> NSButton {
    let button = NSButton(title: spec.title, target: nil, action: nil)
    button.bezelStyle = .glass
    button.borderShape = .capsule
    button.controlSize = .extraLarge
    if spec.role == .default {
      button.tintProminence = .primary
    }
    let hint: String? =
      switch spec.role {
      case .default: "↩"
      case .cancel: "esc"
      case .other: nil
      }
    if let hint {
      // The key that presses it, after the title and fainter.
      let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .large))
      let title = NSMutableAttributedString(
        string: spec.title, attributes: [.font: font])
      title.append(
        NSAttributedString(
          string: "  " + hint,
          attributes: [
            .font: NSFont.systemFont(
              ofSize: font.pointSize - 2, weight: .medium),
            // On the tinted button, white; the others are glass.
            .foregroundColor: spec.role == .default
              ? NSColor.white.withAlphaComponent(0.6) : .tertiaryLabelColor,
          ]))
      button.attributedTitle = title
    }
    button.widthAnchor.constraint(
      greaterThanOrEqualToConstant: Metrics.buttonMinWidth
    ).isActive = true
    return button
  }

  @objc private func buttonPressed(_ sender: NSButton) {
    buttons.first { $0.0 === sender }?.1.action()
  }

  private func press(_ role: Button.Role) {
    guard let (button, _) = buttons.first(where: { $0.1.role == role }) else {
      return
    }
    button.performClick(nil)
  }

  // MARK: Events

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76:  // Return, Enter
      press(.default)
    case 53:  // Escape
      press(.cancel)
    default:
      // Tab and Space reach a focused button through the window; anything
      // else is dropped, rather than reaching the page.
      super.keyDown(with: event)
    }
  }

  /// The menu's shortcuts wait until the prompt is answered.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    true
  }

  // It covers the window, so clicks and scrolls anywhere but its buttons stop
  // here, out of the page's reach.
  override func mouseDown(with event: NSEvent) {}
  override func rightMouseDown(with event: NSEvent) {}
  override func otherMouseDown(with event: NSEvent) {}
  override func scrollWheel(with event: NSEvent) {}
}
