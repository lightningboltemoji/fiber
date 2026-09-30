import AppKit

/// What a window waits on the user for, over its veil (see
/// BrowserWindowController.present(_:)). While it's up it has the window's
/// clicks, scrolls, keyboard focus and menu shortcuts, as a modal alert would.
@MainActor
protocol VeilContent: NSView {
  /// Called if it goes without being answered or dismissed by its owner:
  /// another took its place, or its window closed.
  var onRemoved: (() -> Void)? { get }
  /// What takes the keyboard focus when it's presented, if not itself.
  var initialFirstResponder: NSView? { get }
}

/// A question over the veil: a title, a message, and a row of buttons.
@MainActor
final class VeilPrompt: NSView, VeilContent {
  struct Button {
    enum Role {
      /// Return presses it; it's tinted.
      case `default`
      /// Tinted, but only a click presses it, and not until the prompt has
      /// been up a moment (`confirmDelay`): for what a page could trick the
      /// user into accepting, like adding an extension.
      case confirm
      /// Escape presses it.
      case cancel
      case other
    }

    var title: String
    var role: Role
    var action: () -> Void
  }

  /// How long a confirm button waits to be pressed once the prompt is up, as
  /// Chrome's extension install dialog does.
  private static let confirmDelay: TimeInterval = 0.5

  private enum Metrics {
    static let maxWidth: CGFloat = 480
    static let iconSize: CGFloat = 64
    static let iconSpacing: CGFloat = 16
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
    set {
      messageLabel.stringValue = newValue
      updateMessageVisibility()
    }
  }

  /// Called if the prompt goes without being answered or dismissed by its
  /// owner: another took its place, or its window closed.
  var onRemoved: (() -> Void)?

  /// Called when Escape is pressed and no button has the cancel role.
  var onEscape: (() -> Void)?

  /// What takes the keyboard focus when the prompt is presented, if not the
  /// prompt: a text field in its accessory, say.
  var initialFirstResponder: NSView?

  private let stack = NSStackView()
  private let titleLabel: NSTextField
  private let messageLabel: NSTextField
  private let messageSpacing: CGFloat
  private let buttonsRow = NSStackView()
  private var buttons: [(NSButton, Button)] = []

  /// `icon` goes at the top, and `eyebrow` over the title, smaller (the site
  /// asking, say). `accessory` goes between the message and the buttons.
  init(
    icon: NSImage? = nil, eyebrow: String? = nil, title: String,
    message: String, accessory: NSView? = nil, buttons: [Button]
  ) {
    titleLabel = Self.makeLabel(
      title, font: .systemFont(ofSize: Metrics.titleSize, weight: .semibold),
      color: .white)
    messageLabel = Self.makeLabel(
      message, font: .systemFont(ofSize: Metrics.messageSize),
      color: .white.withAlphaComponent(0.8))
    messageSpacing =
      accessory == nil ? Metrics.buttonsSpacing : Metrics.accessorySpacing
    super.init(frame: .zero)
    // Dark glass, and white text brighter than the system's secondary colors:
    // over a white page, the veil is only a mid gray.
    appearance = NSAppearance(named: .darkAqua)

    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    if let icon {
      let iconView = NSImageView(image: icon)
      iconView.imageScaling = .scaleProportionallyUpOrDown
      NSLayoutConstraint.activate([
        iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
        iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
      ])
      stack.addArrangedSubview(iconView)
      stack.setCustomSpacing(Metrics.iconSpacing, after: iconView)
    }
    if let eyebrow, !eyebrow.isEmpty {
      let label = Self.makeLabel(
        eyebrow, font: .systemFont(ofSize: Metrics.eyebrowSize, weight: .medium),
        color: .white.withAlphaComponent(0.65))
      stack.addArrangedSubview(label)
      stack.setCustomSpacing(Metrics.eyebrowSpacing, after: label)
    }
    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(messageLabel)
    stack.setCustomSpacing(messageSpacing, after: messageLabel)
    // An empty message takes no room (see updateMessageVisibility()).
    stack.detachesHiddenViews = true
    updateMessageVisibility()
    if let accessory {
      stack.addArrangedSubview(accessory)
      stack.setCustomSpacing(Metrics.buttonsSpacing, after: accessory)
    }

    buttonsRow.orientation = .horizontal
    buttonsRow.spacing = Metrics.buttonSpacing
    for spec in buttons {
      let button = Self.makeButton(spec)
      button.target = self
      button.action = #selector(buttonPressed(_:))
      // Enabled once the prompt has been up a moment; see
      // viewDidMoveToWindow().
      if spec.role == .confirm {
        button.isEnabled = false
      }
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

  /// Hides an empty message, and spaces what follows it from the title
  /// instead.
  private func updateMessageVisibility() {
    messageLabel.isHidden = messageLabel.stringValue.isEmpty
    stack.setCustomSpacing(
      messageLabel.isHidden ? messageSpacing : Metrics.titleSpacing,
      after: titleLabel)
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
    if spec.role == .default || spec.role == .confirm {
      button.tintProminence = .primary
    }
    let hint: String? =
      switch spec.role {
      case .default: "↩"
      case .cancel: "esc"
      case .confirm, .other: nil
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
            .foregroundColor: spec.role == .default || spec.role == .confirm
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

  func pressDefaultButton() {
    press(.default)
  }

  /// Presses the cancel button, or, without one, calls onEscape.
  func pressEscape() {
    if buttons.contains(where: { $0.1.role == .cancel }) {
      press(.cancel)
    } else {
      onEscape?()
    }
  }

  private func press(_ role: Button.Role) {
    guard let (button, _) = buttons.first(where: { $0.1.role == role }) else {
      return
    }
    button.performClick(nil)
  }

  // MARK: Events

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else {
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmDelay) {
      [weak self] in
      MainActor.assumeIsolated {
        for (button, spec) in self?.buttons ?? [] where spec.role == .confirm {
          button.isEnabled = true
        }
      }
    }
  }

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76:  // Return, Enter
      press(.default)
    case 53:  // Escape
      pressEscape()
    default:
      // Tab and Space reach a focused button through the window; anything
      // else is dropped, rather than reaching the page.
      super.keyDown(with: event)
    }
  }

  /// The menu's shortcuts wait until the prompt is answered, but for editing
  /// the text in its fields.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let editor = window?.firstResponder as? NSText,
      editor.isDescendant(of: self),
      let action = Self.editingAction(for: event)
    {
      NSApp.sendAction(action, to: nil, from: self)
    }
    return true
  }

  static func editingAction(for event: NSEvent) -> Selector? {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch (event.charactersIgnoringModifiers?.lowercased(), modifiers) {
    case ("x", .command): return #selector(NSText.cut(_:))
    case ("c", .command): return #selector(NSText.copy(_:))
    case ("v", .command): return #selector(NSText.paste(_:))
    case ("a", .command): return #selector(NSText.selectAll(_:))
    case ("z", .command): return Selector(("undo:"))
    case ("z", [.command, .shift]): return Selector(("redo:"))
    default: return nil
    }
  }

  // It covers the window, so clicks and scrolls anywhere but its buttons stop
  // here, out of the page's reach.
  override func mouseDown(with event: NSEvent) {}
  override func rightMouseDown(with event: NSEvent) {}
  override func otherMouseDown(with event: NSEvent) {}
  override func scrollWheel(with event: NSEvent) {}
}
