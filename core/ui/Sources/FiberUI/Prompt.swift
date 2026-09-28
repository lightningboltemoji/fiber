import AppKit
import FiberBridge

@objc @implementation extension FiberPromptButton {
  let buttonID: Int
  let title: String
  let role: FiberPromptButtonRole

  init(buttonID: Int, title: String, role: FiberPromptButtonRole) {
    self.buttonID = buttonID
    self.title = title
    self.role = role
    super.init()
  }
}

@objc @implementation extension FiberPromptListItem {
  let text: String
  let detail: String

  init(text: String, detail: String) {
    self.text = text
    self.detail = detail
    super.init()
  }
}

@objc @implementation extension FiberPromptContent {
  let icon: NSImage?
  let eyebrow: String
  let title: String
  let message: String
  let listHeading: String
  let listItems: [FiberPromptListItem]
  let buttons: [FiberPromptButton]

  init(
    icon: NSImage?, eyebrow: String, title: String, message: String,
    listHeading: String, listItems: [FiberPromptListItem],
    buttons: [FiberPromptButton]
  ) {
    self.icon = icon
    self.eyebrow = eyebrow
    self.title = title
    self.message = message
    self.listHeading = listHeading
    self.listItems = listItems
    self.buttons = buttons
    super.init()
  }
}

@objc @implementation extension FiberPromptFactory {
  @objc(promptWithContent:window:actions:)
  class func prompt(
    with content: FiberPromptContent, window: NSWindow,
    actions: any FiberPromptActions
  ) -> any FiberPrompt {
    Prompt(content: content, window: window, actions: actions)
  }
}

/// Something the browser asks the user over the veiled page (adding an
/// extension, say): Chrome's words, in a VeilPrompt.
@MainActor
final class Prompt: NSObject, FiberPrompt {
  private let actions: any FiberPromptActions
  private weak var controller: BrowserWindowController?
  private var prompt: VeilPrompt?
  private var isDone = false

  init(
    content: FiberPromptContent, window: NSWindow,
    actions: any FiberPromptActions
  ) {
    self.actions = actions
    controller = BrowserWindowController.controller(for: window)
    super.init()
    let prompt = VeilPrompt(
      icon: content.icon, eyebrow: content.eyebrow, title: content.title,
      message: content.message,
      accessory: content.listItems.isEmpty
        ? nil
        : PromptList(heading: content.listHeading, items: content.listItems),
      buttons: content.buttons.map { button in
        .init(title: button.title, role: VeilPrompt.Button.Role(button.role)) {
          [weak self] in
          self?.finish { $0.promptDidPressButton(withID: button.buttonID) }
        }
      })
    prompt.onRemoved = { [weak self] in
      self?.finish(removing: false) { $0.promptDidDismiss() }
    }
    self.prompt = prompt
    guard let controller else {
      // Nowhere to ask; after returning, since the answer can end the
      // prompt's owner.
      DispatchQueue.main.async {
        self.finish { $0.promptDidDismiss() }
      }
      return
    }
    controller.present(prompt)
  }

  func close() {
    finish { $0.promptDidDismiss() }
  }

  /// Takes the prompt down, unless it's already gone, and reports how it
  /// ended, once.
  private func finish(
    removing: Bool = true, _ report: (any FiberPromptActions) -> Void
  ) {
    guard !isDone else {
      return
    }
    isDone = true
    if removing, let prompt {
      controller?.dismiss(prompt)
    }
    report(actions)
  }
}

extension VeilPrompt.Button.Role {
  init(_ role: FiberPromptButtonRole) {
    switch role {
    case .default: self = .default
    case .confirm: self = .confirm
    case .cancel: self = .cancel
    default: self = .other
    }
  }
}

/// A prompt's list, under a heading: what an extension asks to do, say. Each
/// item's detail goes under it, smaller.
@MainActor
private final class PromptList: NSStackView {
  private static let width: CGFloat = 400
  private static let textSize: CGFloat = 14
  private static let detailSize: CGFloat = 12
  private static let itemSpacing: CGFloat = 8
  private static let bulletIndent: CGFloat = 16

  init(heading: String, items: [FiberPromptListItem]) {
    super.init(frame: .zero)
    orientation = .vertical
    alignment = .leading
    spacing = Self.itemSpacing
    if !heading.isEmpty {
      addArrangedSubview(
        Self.makeLabel(
          heading, font: .systemFont(ofSize: Self.textSize, weight: .semibold),
          color: .white.withAlphaComponent(0.9)))
    }
    for item in items {
      addArrangedSubview(Self.makeItem(item))
    }
    widthAnchor.constraint(equalToConstant: Self.width).isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  private static func makeItem(_ item: FiberPromptListItem) -> NSView {
    let bullet = makeLabel(
      "•", font: .systemFont(ofSize: textSize),
      color: .white.withAlphaComponent(0.6))
    let lines = NSStackView()
    lines.orientation = .vertical
    lines.alignment = .leading
    lines.spacing = 2
    lines.addArrangedSubview(
      makeLabel(
        item.text, font: .systemFont(ofSize: textSize),
        color: .white.withAlphaComponent(0.85)))
    if !item.detail.isEmpty {
      lines.addArrangedSubview(
        makeLabel(
          item.detail, font: .systemFont(ofSize: detailSize),
          color: .white.withAlphaComponent(0.6)))
    }
    let row = NSStackView(views: [bullet, lines])
    row.orientation = .horizontal
    row.alignment = .top
    row.spacing = 0
    bullet.widthAnchor.constraint(equalToConstant: bulletIndent).isActive = true
    lines.widthAnchor.constraint(equalToConstant: width - bulletIndent)
      .isActive = true
    return row
  }

  private static func makeLabel(_ text: String, font: NSFont, color: NSColor)
    -> NSTextField
  {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = font
    label.textColor = color
    label.isSelectable = false
    return label
  }
}
