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

@objc @implementation extension FiberPromptField {
  let placeholder: String
  let text: String
  let secure: Bool

  init(placeholder: String, text: String, secure: Bool) {
    self.placeholder = placeholder
    self.text = text
    self.secure = secure
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
  let fields: [FiberPromptField]
  let checkboxTitle: String
  let buttons: [FiberPromptButton]

  convenience init(
    icon: NSImage?, eyebrow: String, title: String, message: String,
    listHeading: String, listItems: [FiberPromptListItem],
    buttons: [FiberPromptButton]
  ) {
    self.init(
      icon: icon, eyebrow: eyebrow, title: title, message: message,
      listHeading: listHeading, listItems: listItems, fields: [],
      checkboxTitle: "", buttons: buttons)
  }

  init(
    icon: NSImage?, eyebrow: String, title: String, message: String,
    listHeading: String, listItems: [FiberPromptListItem],
    fields: [FiberPromptField], checkboxTitle: String,
    buttons: [FiberPromptButton]
  ) {
    self.icon = icon
    self.eyebrow = eyebrow
    self.title = title
    self.message = message
    self.listHeading = listHeading
    self.listItems = listItems
    self.fields = fields
    self.checkboxTitle = checkboxTitle
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

  @objc(bubbleWithContent:tabID:window:actions:)
  class func bubble(
    with content: FiberPromptContent, tabID: Int, window: NSWindow,
    actions: any FiberPromptActions
  ) -> any FiberPrompt {
    BubblePrompt(
      content: content, tabID: tabID, window: window, actions: actions)
  }
}

/// Something the browser asks the user over the veiled page (adding an
/// extension, say): Chrome's words, in a VeilPrompt.
@MainActor
final class Prompt: NSObject, FiberPrompt {
  private let actions: any FiberPromptActions
  private weak var controller: BrowserWindowController?
  private var prompt: VeilPrompt?
  private let form: PromptForm?
  private var isDone = false

  init(
    content: FiberPromptContent, window: NSWindow,
    actions: any FiberPromptActions
  ) {
    self.actions = actions
    controller = BrowserWindowController.controller(for: window)
    form =
      content.fields.isEmpty && content.checkboxTitle.isEmpty
      ? nil
      : PromptForm(fields: content.fields, checkboxTitle: content.checkboxTitle)
    super.init()
    let list =
      content.listItems.isEmpty
      ? nil : PromptList(heading: content.listHeading, items: content.listItems)
    let prompt = VeilPrompt(
      icon: content.icon, eyebrow: content.eyebrow, title: content.title,
      message: content.message,
      accessory: Self.accessory([list, form].compactMap { $0 }),
      buttons: content.buttons.map { button in
        .init(title: button.title, role: VeilPrompt.Button.Role(button.role)) {
          [weak self] in
          self?.finish { $0.promptDidPressButton(withID: button.buttonID) }
        }
      })
    prompt.onRemoved = { [weak self] in
      self?.finish(removing: false) { $0.promptDidDismiss() }
    }
    prompt.onEscape = { [weak self] in
      self?.finish { $0.promptDidDismiss() }
    }
    form?.onSubmit = { [weak prompt] in prompt?.pressDefaultButton() }
    form?.onCancel = { [weak prompt] in prompt?.pressEscape() }
    prompt.initialFirstResponder = form?.firstField
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

  var fieldValues: [String] { form?.values ?? [] }
  var checkboxChecked: Bool { form?.isChecked ?? false }

  func close() {
    finish { $0.promptDidDismiss() }
  }

  private static let accessorySpacing: CGFloat = 20

  /// The views between the message and the buttons, one over the next.
  private static func accessory(_ views: [NSView]) -> NSView? {
    guard views.count > 1 else {
      return views.first
    }
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.spacing = accessorySpacing
    return stack
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

/// A prompt's list, under a heading: what an extension asks to do, say.
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

/// A prompt's text fields and checkbox: a username and password, say.
@MainActor
private final class PromptForm: NSStackView, NSTextFieldDelegate {
  private static let fieldWidth: CGFloat = 320
  private static let checkboxMaxWidth: CGFloat = 400
  private static let fieldSpacing: CGFloat = 10
  private static let checkboxSpacing: CGFloat = 16
  private static let checkboxLabelSpacing: CGFloat = 6

  /// Return and Escape in a field.
  var onSubmit: (() -> Void)?
  var onCancel: (() -> Void)?

  private let textFields: [NSTextField]
  private let checkbox: NSButton?

  var firstField: NSTextField? { textFields.first }
  var values: [String] { textFields.map(\.stringValue) }
  var isChecked: Bool { checkbox?.state == .on }

  init(fields: [FiberPromptField], checkboxTitle: String) {
    textFields = fields.map { field in
      let textField =
        field.secure
        ? NSSecureTextField(string: field.text) : NSTextField(string: field.text)
      textField.placeholderString = field.placeholder
      textField.bezelStyle = .roundedBezel
      textField.controlSize = .large
      textField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
      return textField
    }
    checkbox =
      checkboxTitle.isEmpty
      ? nil : NSButton(checkboxWithTitle: "", target: nil, action: nil)
    super.init(frame: .zero)
    orientation = .vertical
    alignment = .centerX
    spacing = Self.fieldSpacing

    for (index, textField) in textFields.enumerated() {
      textField.delegate = self
      textField.nextKeyView =
        index + 1 < textFields.count
        ? textFields[index + 1] : checkbox ?? textFields.first
      addArrangedSubview(textField)
      textField.widthAnchor.constraint(equalToConstant: Self.fieldWidth)
        .isActive = true
    }
    if let checkbox {
      checkbox.nextKeyView = textFields.first
      let row = Self.makeCheckboxRow(checkbox, title: checkboxTitle)
      if let last = textFields.last {
        setCustomSpacing(Self.checkboxSpacing, after: last)
      }
      addArrangedSubview(row)
    }
  }

  /// `checkbox` with `title` beside it, wrapped rather than cut short, as a
  /// button's title would be; clicking the title toggles the checkbox.
  private static func makeCheckboxRow(_ checkbox: NSButton, title: String)
    -> NSView
  {
    checkbox.setAccessibilityLabel(title)
    let label = NSTextField(wrappingLabelWithString: title)
    label.font = .systemFont(ofSize: NSFont.systemFontSize)
    label.textColor = .white.withAlphaComponent(0.85)
    label.isSelectable = false
    label.setAccessibilityElement(false)
    label.addGestureRecognizer(
      NSClickGestureRecognizer(
        target: checkbox, action: #selector(NSButton.performClick(_:))))
    label.widthAnchor.constraint(lessThanOrEqualToConstant: checkboxMaxWidth)
      .isActive = true
    let row = NSStackView(views: [checkbox, label])
    row.orientation = .horizontal
    row.alignment = .firstBaseline
    row.spacing = checkboxLabelSpacing
    return row
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // A field editor takes Return and Escape before the prompt sees them.
  func control(
    _ control: NSControl, textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      onSubmit?()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      onCancel?()
      return true
    default:
      return false
    }
  }
}
