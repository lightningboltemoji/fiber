import AppKit
import FiberBridge

/// The window's find bar (Command-F): a glass capsule (GlassCapsule), with
/// the field, the count, previous and next, and close. It's Chrome's find in
/// page underneath (see FiberFindBar), which shows and hides it.
@MainActor
final class FindBar: NSView, FiberFindBar {
  static let width: CGFloat = 320
  static let height = GlassCapsule.height
  private static let rimWidth = GlassCapsule.rimWidth
  private static let endInset = GlassCapsule.endInset
  private static let fieldInset: CGFloat = 12
  private static let noMatchesTint = NSColor.systemRed.withAlphaComponent(0.3)

  var actions: (any FiberFindBarActions)?
  /// Called as the browser gives the bar the keyboard, for what else had it
  /// (the omnibar, the command palette) to close.
  var onOpen: () -> Void = {}
  var onShowOrHide: () -> Void = {}
  private(set) var isOpen = false

  private let glass = RimmedGlassView(rimWidth: FindBar.rimWidth)
  private let field = NSTextField()
  private let countLabel = NSTextField(labelWithString: "")
  private let previousButton = GlassCapsule.makeButton(
    symbol: "chevron.up", label: "Previous")
  private let nextButton = GlassCapsule.makeButton(
    symbol: "chevron.down", label: "Next")
  private let closeButton = GlassCapsule.makeButton(symbol: "xmark", label: "Close")
  private var matchCount = -1
  /// Set while the browser's text goes into the field, so it isn't reported
  /// back as the user's.
  private var isApplyingText = false
  private var reportedFocus = false

  init() {
    super.init(frame: .zero)
    isHidden = true
    alphaValue = 0
    glass.cornerRadius = Self.height / 2
    glass.contentView = makeContent()
    addSubview(glass)
    setMatchCount(-1, activeMatch: 0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    glass.frame = bounds
  }

  // MARK: FiberFindBar

  var text: String {
    (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
  }

  var selectedRange: NSRange {
    field.currentEditor()?.selectedRange ?? NSRange(location: 0, length: 0)
  }

  var hasFocus: Bool {
    guard let editor = field.currentEditor() else {
      return false
    }
    return window?.firstResponder === editor
  }

  func show(animated: Bool, focus: Bool) {
    if !isOpen {
      isOpen = true
      isHidden = false
      onShowOrHide()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = animated ? 0.15 : 0
        animator().alphaValue = 1
      }
    }
    if focus {
      takeKeyboard()
    }
  }

  func hide(animated: Bool) {
    guard isOpen else {
      return
    }
    isOpen = false
    onShowOrHide()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated ? 0.12 : 0
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        // Hidden, so the field doesn't take clicks or focus.
        if let self, !self.isOpen {
          self.isHidden = true
        }
      }
    }
  }

  func focusAndSelectAll() {
    takeKeyboard()
    field.currentEditor()?.selectAll(nil)
  }

  func setText(_ text: String, selectedRange: NSRange) {
    defer { updateButtons() }
    guard let editor = field.currentEditor() as? NSTextView else {
      field.stringValue = text
      return
    }
    if editor.hasMarkedText() {
      return
    }
    if editor.string != text {
      // As an edit, so the field editor resizes to the text and scrolls.
      isApplyingText = true
      let all = NSRange(location: 0, length: (editor.string as NSString).length)
      if editor.shouldChangeText(in: all, replacementString: text) {
        editor.replaceCharacters(in: all, with: text)
        editor.didChangeText()
      }
      isApplyingText = false
    }
    let length = (text as NSString).length
    let location = min(selectedRange.location, length)
    editor.setSelectedRange(
      NSRange(
        location: location,
        length: min(selectedRange.length, length - location)))
  }

  func setMatchCount(_ count: Int, activeMatch: Int) {
    matchCount = count
    countLabel.stringValue = Self.countText(count, activeMatch: activeMatch)
    countLabel.isHidden = countLabel.stringValue.isEmpty
    glass.contentTintColor = count == 0 ? Self.noMatchesTint : nil
    updateButtons()
  }

  /// "3 of 12", or before the user moves to a match, "12 matches".
  static func countText(_ count: Int, activeMatch: Int) -> String {
    switch count {
    case ..<0:
      ""
    case 0:
      "No matches"
    case _ where activeMatch > 0:
      "\(activeMatch.formatted()) of \(count.formatted())"
    case 1:
      "1 match"
    default:
      "\(count.formatted()) matches"
    }
  }

  // MARK: Focus

  /// Tells the browser when the field takes the keyboard or gives it up. The
  /// window calls it as its first responder changes.
  func firstResponderDidChange() {
    let focused = hasFocus
    if focused != reportedFocus {
      reportedFocus = focused
      actions?.findBarFocusDidChange(focused)
    }
  }

  private func takeKeyboard() {
    onOpen()
    if !hasFocus {
      window?.makeFirstResponder(field)
    }
  }

  // MARK: Content

  private func makeContent() -> NSView {
    let content = FindBarContent()
    content.onClick = { [weak self] in
      guard let self else {
        return
      }
      self.window?.makeFirstResponder(self.field)
    }

    field.isBezeled = false
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingTail
    field.cell?.isScrollable = true
    field.cell?.sendsActionOnEndEditing = false
    field.font = .systemFont(ofSize: NSFont.systemFontSize)
    field.placeholderString = "Find in Page"
    // Without a content type, AppKit's AutoFill guesses one, and offers
    // one-time codes in a list that flashes up under the field as it focuses.
    field.contentType = .URL
    field.delegate = self
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    countLabel.textColor = .secondaryLabelColor
    countLabel.setContentHuggingPriority(.required, for: .horizontal)
    countLabel.setContentCompressionResistancePriority(
      .required, for: .horizontal)

    for (button, action) in [
      (previousButton, #selector(findPrevious(_:))),
      (nextButton, #selector(findNext(_:))),
      (closeButton, #selector(close(_:))),
    ] {
      button.target = self
      button.action = action
    }

    let buttons = NSStackView(views: [previousButton, nextButton, closeButton])
    buttons.spacing = 0
    for view in [field, countLabel, buttons] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(
        equalTo: content.leadingAnchor, constant: Self.fieldInset),
      field.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      countLabel.leadingAnchor.constraint(
        equalTo: field.trailingAnchor, constant: 6),
      countLabel.firstBaselineAnchor.constraint(
        equalTo: field.firstBaselineAnchor),
      buttons.leadingAnchor.constraint(
        equalTo: countLabel.trailingAnchor, constant: 4),
      buttons.trailingAnchor.constraint(
        equalTo: content.trailingAnchor, constant: -Self.endInset),
      buttons.centerYAnchor.constraint(equalTo: content.centerYAnchor),
    ])
    return content
  }

  private func updateButtons() {
    let canFind = !text.isEmpty && matchCount != 0
    previousButton.isEnabled = canFind
    nextButton.isEnabled = canFind
  }

  @objc private func findPrevious(_ sender: Any?) {
    actions?.findBarFindPrevious()
  }

  @objc private func findNext(_ sender: Any?) {
    actions?.findBarFindNext()
  }

  @objc private func close(_ sender: Any?) {
    actions?.findBarClose()
  }
}

extension FindBar: NSTextFieldDelegate {
  func controlTextDidChange(_ notification: Notification) {
    updateButtons()
    // What an input method is composing isn't what the user is looking for
    // yet.
    guard !isApplyingText,
      let editor = field.currentEditor() as? NSTextView,
      !editor.hasMarkedText()
    else {
      return
    }
    actions?.findBarTextDidChange(editor.string)
  }

  func control(
    _ control: NSControl, textView: NSTextView,
    doCommandBy selector: Selector
  ) -> Bool {
    switch selector {
    case #selector(NSResponder.insertNewline(_:)):
      if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
        actions?.findBarFindPrevious()
      } else {
        actions?.findBarFindNext()
      }
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      actions?.findBarClose()
      return true
    default:
      return false
    }
  }
}

/// Clicks on the capsule around the controls focus the field, and don't move
/// the window or reach the page.
private final class FindBarContent: NSView {
  var onClick: () -> Void = {}

  override var mouseDownCanMoveWindow: Bool { false }

  override func mouseDown(with event: NSEvent) {
    onClick()
  }
}
