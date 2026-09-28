import AppKit
import FiberBridge

/// Fiber's command palette, opened with Command-L or by clicking the toolbar's
/// address. It's Chrome's omnibox underneath (see FiberOmnibox): the browser
/// fills in the field and lists the suggestions. Covers the window while open.
@MainActor
final class CommandPalette: NSView, FiberOmnibox {
  private static let maxWidth: CGFloat = 640
  private static let sideMargin: CGFloat = 32
  /// The panel's top sits this far down the window, and at least `minTop`.
  private static let topFraction: CGFloat = 0.2
  private static let minTop: CGFloat = 72
  /// Space kept below the panel when there are more suggestions than fit.
  private static let bottomMargin: CGFloat = 24
  private static let cornerRadius: CGFloat = 26
  private static let rimWidth: CGFloat = 6
  private static let fieldRowHeight: CGFloat = 56
  private static let footerHeight: CGFloat = 30
  private static let horizontalInset: CGFloat = 18

  var actions: (any FiberOmniboxActions)?
  var onOpen: () -> Void = {}
  /// Called when the palette is done: the user opened something from it,
  /// pressed Escape, or clicked outside it. Its owner closes it.
  var onDismiss: () -> Void = {}
  private(set) var isOpen = false

  private let shadowView = OutsetShadowView()
  private let panel = RimmedGlassView(rimWidth: CommandPalette.rimWidth)
  private let content = PaletteContentView()
  private let field = NSTextField()
  private let keywordChip = KeywordChip()
  private let suggestionsScrollView = NSScrollView()
  private let suggestions = SuggestionList()

  /// The field's text and selection as last sent to or from the browser.
  /// Changes the field makes on its own (the user's) are the ones that differ.
  private var lastText = ""
  private var lastSelection = NSRange(location: 0, length: 0)
  /// Set while the browser's text goes into the field, so it isn't reported
  /// back as the user's.
  private var isApplyingText = false
  private var isSelectionReportScheduled = false
  private var hasKeyword = false
  /// The part of the selected suggestion that Return acts on.
  private var selectedPart = FiberSuggestionPart.row

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
    isHidden = true
    alphaValue = 0

    shadowView.cornerRadius = Self.cornerRadius
    addSubview(shadowView)
    panel.cornerRadius = Self.cornerRadius
    configureContent()
    panel.contentView = content
    addSubview(panel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // MARK: FiberOmnibox

  func focus() {
    guard !isOpen else {
      // Command-L again: everything selected, ready to replace.
      field.currentEditor()?.selectAll(nil)
      return
    }
    isOpen = true
    // Whatever the last opening left; the browser sends what's current.
    suggestions.setSuggestions([])
    selectedPart = .row
    layoutPanel()
    isHidden = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      animator().alphaValue = 1
    }
    onOpen()
    window?.makeFirstResponder(field)
    if let editor = field.currentEditor() {
      NotificationCenter.default.addObserver(
        self, selector: #selector(fieldSelectionDidChange(_:)),
        name: NSTextView.didChangeSelectionNotification, object: editor)
    }
    // The browser fills in the field: the page's URL, all selected.
    actions?.omniboxDidFocus()
  }

  func setText(_ text: String, selectedRange: NSRange) {
    // It's reset as the palette closes; the next opening sends it again.
    guard isOpen else {
      return
    }
    lastText = text
    lastSelection = selectedRange
    guard let editor = field.currentEditor() as? NSTextView else {
      field.stringValue = text
      return
    }
    // What an input method is composing stays until it's done.
    if editor.hasMarkedText()
      || (editor.string == text && editor.selectedRange() == selectedRange)
    {
      return
    }
    isApplyingText = true
    if editor.string != text {
      // As an edit, so the field editor resizes to the text and scrolls (it's
      // sized to its text in a scrolling field, and setting `string` alone
      // leaves it at the old size).
      let all = NSRange(location: 0, length: (editor.string as NSString).length)
      if editor.shouldChangeText(in: all, replacementString: text) {
        editor.replaceCharacters(in: all, with: text)
        editor.didChangeText()
      }
    }
    let length = (text as NSString).length
    let location = min(selectedRange.location, length)
    editor.setSelectedRange(
      NSRange(
        location: location,
        length: min(selectedRange.length, length - location)))
    // The start of a long URL, or the caret.
    editor.scrollRangeToVisible(NSRange(location: location, length: 0))
    isApplyingText = false
  }

  func setKeywordLabel(_ label: String) {
    guard isOpen else {
      return
    }
    hasKeyword = !label.isEmpty
    keywordChip.title = label
    keywordChip.isHidden = !hasKeyword
    content.fieldRow?.needsLayout = true
  }

  func setSuggestions(_ newSuggestions: [FiberSuggestion]) {
    guard isOpen else {
      return
    }
    suggestions.setSuggestions(newSuggestions)
    layoutPanel()
  }

  func setSelectedSuggestionIndex(
    _ index: Int, part: FiberSuggestionPart, actionIndex: Int
  ) {
    guard isOpen else {
      return
    }
    selectedPart = part
    suggestions.setSelection(index: index, part: part, actionIndex: actionIndex)
  }

  // MARK: Opening and closing

  func close() {
    guard isOpen else {
      return
    }
    isOpen = false
    if let editor = field.currentEditor() {
      NotificationCenter.default.removeObserver(
        self, name: NSTextView.didChangeSelectionNotification, object: editor)
      window?.makeFirstResponder(nil)
    }
    // Discards what the user typed, and the suggestions.
    actions?.omniboxDidBlur()
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

  // MARK: Layout

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    layoutPanel()
  }

  /// The panel, sized to show the suggestions, as many as fit.
  private func layoutPanel() {
    let width = min(Self.maxWidth, bounds.width - 2 * Self.sideMargin)
    let top = max((bounds.height * Self.topFraction).rounded(), Self.minTop)
    let fixedHeight =
      2 * Self.rimWidth + Self.fieldRowHeight + 1 + Self.footerHeight
    let availableHeight = max(
      bounds.height - top - Self.bottomMargin - fixedHeight, 0)
    let listHeight = min(suggestions.contentHeight, availableHeight)
    content.listHeight = listHeight
    let height = fixedHeight + listHeight
    panel.frame = NSRect(
      x: ((bounds.width - width) / 2).rounded(), y: bounds.height - top - height,
      width: width, height: height)
    shadowView.frame = panel.frame
    suggestions.frame.size = NSSize(
      width: width - 2 * Self.rimWidth, height: suggestions.contentHeight)
  }

  // MARK: Events

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if !panel.frame.contains(point) {
      onDismiss()
    }
  }

  // The page under the dimming doesn't scroll.
  override func scrollWheel(with event: NSEvent) {}

  /// Return, or the accessibility Confirm action: opens the selected
  /// suggestion, or what's typed.
  @objc private func submit(_ sender: Any?) {
    guard !field.stringValue.isEmpty || hasKeyword else {
      return
    }
    let part = selectedPart
    actions?.omniboxOpenSelection(with: NSApp.currentEvent)
    if Self.opensSomething(part) {
      onDismiss()
    }
  }

  /// Whether Return or a click on `part` opens something, which the palette
  /// closes for. The rest change the suggestions: the keyword button starts
  /// keyword mode, in the field, and the remove button removes one.
  private static func opensSomething(_ part: FiberSuggestionPart) -> Bool {
    part != .keyword && part != .remove
  }

  /// Reports the user's edit (typing, deleting, pasting, moving the caret) to
  /// the browser, which autocompletes and suggests.
  private func reportEdit() {
    guard !isApplyingText, let editor = field.currentEditor() as? NSTextView
    else {
      return
    }
    lastText = editor.string
    lastSelection = editor.selectedRange()
    actions?.omniboxTextDidChange(
      lastText, selectedRange: lastSelection, composing: editor.hasMarkedText())
  }

  /// The caret moved, or the selection changed. Reported once the event that
  /// moved it is done, so the browser's answer (like accepting an inline
  /// autocompletion) doesn't land mid-edit. Text changes report themselves.
  @objc private func fieldSelectionDidChange(_ notification: Notification) {
    guard !isApplyingText, !isSelectionReportScheduled else {
      return
    }
    isSelectionReportScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else {
          return
        }
        self.isSelectionReportScheduled = false
        guard self.isOpen,
          let editor = self.field.currentEditor() as? NSTextView,
          editor.string != self.lastText
            || editor.selectedRange() != self.lastSelection
        else {
          return
        }
        self.reportEdit()
      }
    }
  }

  // MARK: Content

  private func configureContent() {
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

    keywordChip.isHidden = true

    content.fieldRow = FieldRowView(
      icon: icon, chip: keywordChip, field: field, inset: Self.horizontalInset)

    suggestions.onOpen = { [weak self] index, part, actionIndex, event in
      guard let self else {
        return
      }
      self.actions?.omniboxOpenSuggestion(
        at: index, part: part, actionIndex: actionIndex, event: event)
      if Self.opensSomething(part) {
        self.onDismiss()
      }
    }
    suggestions.onRemove = { [weak self] index in
      self?.actions?.omniboxRemoveSuggestion(at: index)
    }
    suggestionsScrollView.documentView = suggestions
    suggestionsScrollView.drawsBackground = false
    suggestionsScrollView.hasVerticalScroller = true
    suggestionsScrollView.autohidesScrollers = true
    suggestionsScrollView.scrollerStyle = .overlay
    content.list = suggestionsScrollView

    let hints = NSTextField(labelWithAttributedString: Self.hints)
    content.hints = hints
    content.fieldRowHeight = Self.fieldRowHeight
    content.footerHeight = Self.footerHeight
    content.horizontalInset = Self.horizontalInset
  }

  /// Command-Return, unlisted, opens a new tab in the background, as in Chrome.
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
  func controlTextDidChange(_ notification: Notification) {
    reportEdit()
  }

  func control(
    _ control: NSControl, textView: NSTextView,
    doCommandBy selector: Selector
  ) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)):
      onDismiss()
    // The browser moves the selection through the suggestions, and puts the
    // selected one's text in the field.
    case #selector(NSResponder.moveUp(_:)):
      actions?.omniboxMoveSelection(.up)
    case #selector(NSResponder.moveDown(_:)):
      actions?.omniboxMoveSelection(.down)
    case #selector(NSResponder.pageUp(_:)),
      #selector(NSResponder.scrollPageUp(_:)):
      actions?.omniboxMoveSelection(.pageUp)
    case #selector(NSResponder.pageDown(_:)),
      #selector(NSResponder.scrollPageDown(_:)):
      actions?.omniboxMoveSelection(.pageDown)
    // Tab steps through the suggestions' parts too, like "Search YouTube".
    case #selector(NSResponder.insertTab(_:)):
      actions?.omniboxMoveSelection(.next)
    case #selector(NSResponder.insertBacktab(_:)):
      actions?.omniboxMoveSelection(.previous)
    // Backspace at the start of the field leaves keyword mode.
    case #selector(NSResponder.deleteBackward(_:)):
      guard hasKeyword, textView.selectedRange() == NSRange(location: 0, length: 0)
      else {
        return false
      }
      actions?.omniboxClearKeyword()
    // Shift-Delete (Shift-Fn-Delete) removes the selected suggestion from
    // history, as in Chrome.
    case #selector(NSResponder.deleteForward(_:)):
      guard NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
        let index = suggestions.selectedRemovableIndex
      else {
        return false
      }
      actions?.omniboxRemoveSuggestion(at: index)
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
    default:
      return false
    }
    return true
  }
}

private final class PaletteContentView: NSView {
  var fieldRow: NSView? {
    didSet { replace(oldValue, with: fieldRow) }
  }
  var list: NSView? {
    didSet { replace(oldValue, with: list) }
  }
  var hints: NSView? {
    didSet { replace(oldValue, with: hints) }
  }
  var listHeight: CGFloat = 0 {
    didSet { needsLayout = true }
  }
  var fieldRowHeight: CGFloat = 0
  var footerHeight: CGFloat = 0
  var horizontalInset: CGFloat = 0

  private let separator = NSBox()

  override init(frame: NSRect) {
    super.init(frame: frame)
    separator.boxType = .separator
    addSubview(separator)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    fieldRow?.frame = NSRect(
      x: 0, y: 0, width: bounds.width, height: fieldRowHeight)
    separator.frame = NSRect(
      x: 0, y: fieldRowHeight, width: bounds.width, height: 1)
    list?.frame = NSRect(
      x: 0, y: fieldRowHeight + 1, width: bounds.width, height: listHeight)
    if let hints {
      let size = hints.fittingSize
      hints.frame = NSRect(
        x: bounds.width - horizontalInset - size.width,
        y: bounds.height - footerHeight + ((footerHeight - size.height) / 2)
          .rounded(),
        width: size.width, height: size.height)
    }
  }

  override func layout() {
    super.layout()
    resizeSubviews(withOldSize: bounds.size)
  }

  private func replace(_ old: NSView?, with new: NSView?) {
    old?.removeFromSuperview()
    if let new {
      addSubview(new)
    }
    needsLayout = true
  }
}

private final class FieldRowView: NSView {
  private static let iconSpacing: CGFloat = 12
  private static let chipSpacing: CGFloat = 8

  private let icon: NSView
  private let chip: NSView
  private let field: NSView
  private let inset: CGFloat

  init(icon: NSView, chip: NSView, field: NSView, inset: CGFloat) {
    self.icon = icon
    self.chip = chip
    self.field = field
    self.inset = inset
    super.init(frame: .zero)
    for view in [icon, chip, field] {
      addSubview(view)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    var x = inset
    func place(_ view: NSView, width: CGFloat, spacing: CGFloat) {
      let height = view.fittingSize.height
      view.frame = NSRect(
        x: x, y: ((bounds.height - height) / 2).rounded(), width: width,
        height: height)
      x += width + spacing
    }
    place(icon, width: icon.fittingSize.width, spacing: Self.iconSpacing)
    if !chip.isHidden {
      place(chip, width: chip.fittingSize.width, spacing: Self.chipSpacing)
    }
    place(field, width: max(bounds.width - inset - x, 0), spacing: 0)
  }

  override func layout() {
    super.layout()
    resizeSubviews(withOldSize: bounds.size)
  }
}

/// Shows where the query goes in keyword mode, like "Search YouTube", before
/// the field's text.
private final class KeywordChip: NSView {
  var title = "" {
    didSet { label.stringValue = title }
  }

  private let label = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.cornerCurve = .continuous
    label.font = .systemFont(ofSize: 15, weight: .medium)
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 28),
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    updateColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.controlAccentColor.cgColor
      label.textColor = .alternateSelectedControlTextColor
    }
  }
}
