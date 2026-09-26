import AppKit

/// Stands in for a tab's web contents: shows the URL, links to other fake
/// pages, and buttons that open JavaScript dialogs.
@MainActor
final class MockPageView: NSView {
  private static let links = [
    "https://fiber.example/",
    "https://fiber.example/about",
    "https://www.example.com/a/rather/long/path/to/show/truncation?query=1",
  ]

  weak var browser: MockBrowser?
  private(set) var title = ""
  var asksBeforeLeaving: Bool { leaveCheckbox.state == .on }

  private let titleLabel = NSTextField(labelWithString: "")
  private let urlLabel = NSTextField(labelWithString: "")
  private let resultLabel = NSTextField(labelWithString: " ")
  private let leaveCheckbox = NSButton(
    checkboxWithTitle: "Ask before leaving (beforeunload)", target: nil,
    action: nil)

  override init(frame: NSRect) {
    super.init(frame: frame)
    titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
    urlLabel.textColor = .secondaryLabelColor
    resultLabel.textColor = .secondaryLabelColor

    let links = Self.links.map { url in
      let link = LinkButton(url: url)
      link.onHover = { [weak self] url in self?.browser?.linkHovered(url) }
      link.onClick = { [weak self] url in
        self?.browser?.linkClicked(url, event: NSApp.currentEvent)
      }
      return link
    }
    let dialogs = NSStackView(views: [
      NSButton(title: "alert()", target: self, action: #selector(alert(_:))),
      NSButton(title: "confirm()", target: self, action: #selector(confirm(_:))),
      NSButton(title: "prompt()", target: self, action: #selector(prompt(_:))),
    ])

    let stack = NSStackView(
      views: [titleLabel, urlLabel] + links + [
        dialogs, resultLabel, leaveCheckbox,
      ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.setCustomSpacing(24, after: urlLabel)
    stack.setCustomSpacing(24, after: links.last!)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 48),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingAnchor, constant: -48),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    dirtyRect.fill()
  }

  func show(url: String, loaded: Bool) {
    let path = URL(string: url)?.path() ?? ""
    title = "\(URL(string: url)?.host() ?? url)\(path == "/" ? "" : path)"
    titleLabel.stringValue = loaded ? title : "Loading…"
    urlLabel.stringValue = url
  }

  @objc private func alert(_ sender: Any?) {
    browser?.showDialog(
      .alert, title: "fiber.example says", message: "Hello from alert()."
    ) { [weak self] result in self?.show(result, of: "alert()") }
  }

  @objc private func confirm(_ sender: Any?) {
    browser?.showDialog(
      .confirm, title: "fiber.example says", message: "Is this a confirm()?"
    ) { [weak self] result in self?.show(result, of: "confirm()") }
  }

  @objc private func prompt(_ sender: Any?) {
    browser?.showDialog(
      .prompt, title: "fiber.example says", message: "What's your name?",
      defaultPromptText: "Fiber"
    ) { [weak self] result in self?.show(result, of: "prompt()") }
  }

  private func show(_ result: MockDialogResult, of call: String) {
    resultLabel.stringValue =
      switch result {
      case .accepted(let input) where !input.isEmpty:
        "\(call) returned “\(input)”"
      case .accepted: "\(call) was accepted"
      case .cancelled: "\(call) was cancelled"
      case .dismissed: "\(call) was dismissed"
      }
  }
}

/// A link: reports hovers (for the status bubble) and clicks.
private final class LinkButton: NSButton {
  let url: String
  var onHover: (String?) -> Void = { _ in }
  var onClick: (String) -> Void = { _ in }

  init(url: String) {
    self.url = url
    super.init(frame: .zero)
    isBordered = false
    attributedTitle = NSAttributedString(
      string: url,
      attributes: [
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
      ])
    target = self
    action = #selector(clicked(_:))
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func mouseEntered(with event: NSEvent) {
    onHover(url)
  }

  override func mouseExited(with event: NSEvent) {
    onHover(nil)
  }

  @objc private func clicked(_ sender: Any?) {
    onClick(url)
  }
}
