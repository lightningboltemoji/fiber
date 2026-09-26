import AppKit

/// Fiber's command palette: a glass panel floating over the top of the page,
/// opened with Command-L or by clicking the toolbar's address. For now it opens
/// pages (type an address or a search and press Return); it's where the rest
/// of Fiber's commands will go.
///
/// This view covers the window's content while open, dimming the page a
/// little; clicking outside the panel dismisses it.
@MainActor
final class CommandPalette: NSView {
  private static let maxWidth: CGFloat = 640
  private static let sideMargin: CGFloat = 32
  /// The panel's top sits this far down the window, and at least `minTop`.
  private static let topFraction: CGFloat = 0.2
  private static let minTop: CGFloat = 72
  private static let cornerRadius: CGFloat = 26
  private static let rimWidth: CGFloat = 6
  private static let fieldRowHeight: CGFloat = 56
  private static let footerHeight: CGFloat = 30
  private static let horizontalInset: CGFloat = 18
  private static var panelHeight: CGFloat {
    2 * rimWidth + fieldRowHeight + 1 + footerHeight
  }

  /// Called with what the user entered, and the key event, on Return (with
  /// or without modifiers).
  var onSubmit: (String, NSEvent?) -> Void = { _, _ in }
  /// Called when the user dismisses the palette: Escape, or a click outside.
  var onDismiss: () -> Void = {}
  private(set) var isOpen = false

  private let shadowView = OutsetShadowView()
  private let panel = RimmedGlassView(rimWidth: CommandPalette.rimWidth)
  private let field = NSTextField()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
    isHidden = true
    alphaValue = 0

    shadowView.cornerRadius = Self.cornerRadius
    addSubview(shadowView)
    panel.cornerRadius = Self.cornerRadius
    panel.contentView = makePanelContent()
    addSubview(panel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Opens the palette with `text` in its field, all selected, or if it's
  /// already open, selects what's there.
  func open(text: String) {
    if !isOpen {
      isOpen = true
      field.stringValue = text
      isHidden = false
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        animator().alphaValue = 1
      }
    }
    if let editor = field.currentEditor() {
      editor.selectAll(nil)
    } else {
      // Selects all of the text as it starts editing.
      window?.makeFirstResponder(field)
    }
  }

  func close() {
    guard isOpen else {
      return
    }
    isOpen = false
    if field.currentEditor() != nil {
      window?.makeFirstResponder(nil)
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        if let self, !self.isOpen {
          self.isHidden = true
        }
      }
    }
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    let width = min(Self.maxWidth, bounds.width - 2 * Self.sideMargin)
    let top = max((bounds.height * Self.topFraction).rounded(), Self.minTop)
    panel.frame = NSRect(
      x: ((bounds.width - width) / 2).rounded(),
      y: bounds.height - top - Self.panelHeight, width: width,
      height: Self.panelHeight)
    shadowView.frame = panel.frame
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if !panel.frame.contains(point) {
      onDismiss()
    }
  }

  // The page under the dimming doesn't scroll.
  override func scrollWheel(with event: NSEvent) {}

  /// The field, with a search icon, above a row of keyboard hints.
  private func makePanelContent() -> NSView {
    let content = NSView()

    let icon = NSImageView(
      image: NSImage(
        systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
    icon.symbolConfiguration = .init(pointSize: 17, weight: .medium)
    icon.contentTintColor = .secondaryLabelColor

    field.isBezeled = false
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingTail
    field.cell?.isScrollable = true
    field.font = .systemFont(ofSize: 20)
    field.placeholderAttributedString = NSAttributedString(
      string: "Search or enter address",
      attributes: [
        .font: NSFont.systemFont(ofSize: 20),
        .foregroundColor: NSColor.tertiaryLabelColor,
      ])
    field.cell?.sendsActionOnEndEditing = false
    field.target = self
    field.action = #selector(submit(_:))
    field.delegate = self

    let separator = NSBox()
    separator.boxType = .separator

    let hints = NSTextField(labelWithAttributedString: Self.hints)

    for view in [icon, field, separator, hints] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    let inset = Self.horizontalInset
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(
        equalTo: content.leadingAnchor, constant: inset),
      icon.centerYAnchor.constraint(
        equalTo: content.topAnchor, constant: Self.fieldRowHeight / 2),
      field.leadingAnchor.constraint(
        equalTo: icon.trailingAnchor, constant: 12),
      field.trailingAnchor.constraint(
        equalTo: content.trailingAnchor, constant: -inset),
      field.centerYAnchor.constraint(equalTo: icon.centerYAnchor),

      separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      separator.topAnchor.constraint(
        equalTo: content.topAnchor, constant: Self.fieldRowHeight),

      hints.trailingAnchor.constraint(
        equalTo: content.trailingAnchor, constant: -inset),
      hints.centerYAnchor.constraint(
        equalTo: content.bottomAnchor, constant: -Self.footerHeight / 2),
    ])
    return content
  }

  /// Return, or the accessibility Confirm action.
  @objc private func submit(_ sender: Any?) {
    let text = field.stringValue.trimmingCharacters(in: .whitespaces)
    if !text.isEmpty {
      onSubmit(text, NSApp.currentEvent)
    }
  }

  /// "Open ↩  New Tab ⌥↩  Close esc", the keys fainter than their actions.
  /// (Command-Return opens a new tab in the background, as in Chrome.)
  private static var hints: NSAttributedString {
    let text = NSMutableAttributedString()
    let hints = [("Open", "↩"), ("New Tab", "⌥↩"), ("Close", "esc")]
    for (index, (action, key)) in hints.enumerated() {
      if index > 0 {
        text.append(NSAttributedString(string: "     "))
      }
      text.append(
        NSAttributedString(
          string: "\(action)  ",
          attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
          ]))
      text.append(
        NSAttributedString(
          string: key,
          attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
          ]))
    }
    return text
  }
}

extension CommandPalette: NSTextFieldDelegate {
  func control(
    _ control: NSControl, textView: NSTextView,
    doCommandBy selector: Selector
  ) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)):
      onDismiss()
      return true
    // Return with modifiers, which the browser reads to decide where to open
    // the page. The field would otherwise insert a line break (Option-Return)
    // or beep (Command-Return, which has no binding: noop:).
    case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
      Selector(("noop:")):
      // Return, or the keypad's Enter.
      guard let event = NSApp.currentEvent, event.type == .keyDown,
        ["\r", "\u{3}"].contains(event.charactersIgnoringModifiers)
      else {
        return false
      }
      submit(nil)
      return true
    default:
      return false
    }
  }
}
