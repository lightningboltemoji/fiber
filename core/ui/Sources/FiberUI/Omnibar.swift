import AppKit
import FiberBridge

/// Fiber's omnibar, opened with Command-L or by clicking the toolbar's
/// address. It's Chrome's omnibox underneath (see FiberOmnibox): the browser
/// fills in the field and lists the suggestions. Covers the window while open.
@MainActor
final class Omnibar: NSObject, FiberOmnibox {
  let view = PaletteView(placeholder: "Search or enter address")
  var actions: (any FiberOmniboxActions)?
  var onOpen: () -> Void = {}
  /// Called when the omnibar is done: the user opened something from it,
  /// pressed Escape, or clicked outside it. Its owner closes it.
  var onDismiss: () -> Void = {} {
    didSet { view.onDismiss = onDismiss }
  }
  var isOpen: Bool { view.isOpen }
  /// The field's own field editor, which the window gives it.
  let fieldEditor = URLFieldEditor()

  private var field: NSTextField { view.field }
  private let keywordChip = KeywordChip()
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

  override init() {
    super.init()
    field.target = self
    field.action = #selector(submit(_:))
    field.delegate = self
    keywordChip.isHidden = true
    view.fieldAccessory = keywordChip
    // Command-Return, unlisted, opens a new tab in the background, as in
    // Chrome.
    view.hints = [("Open", "↩"), ("New Tab", "⌥↩"), ("Close", "esc")]

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
    view.list = suggestions
  }

  // MARK: FiberOmnibox

  func focus() {
    guard !isOpen else {
      // Command-L again: everything selected, ready to replace.
      field.currentEditor()?.selectAll(nil)
      return
    }
    // Whatever the last opening left; the browser sends what's current.
    suggestions.setSuggestions([])
    view.listContentHeight = 0
    selectedPart = .row
    onOpen()
    view.open()
    if let editor = field.currentEditor() {
      NotificationCenter.default.addObserver(
        self, selector: #selector(fieldSelectionDidChange(_:)),
        name: NSTextView.didChangeSelectionNotification, object: editor)
    }
    // The browser fills in the field: the page's URL, all selected.
    actions?.omniboxDidFocus()
  }

  func setText(_ text: String, selectedRange: NSRange) {
    // It's reset as the omnibar closes; the next opening sends it again.
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
    view.fieldAccessoryDidResize()
  }

  func setSuggestions(_ newSuggestions: [FiberSuggestion]) {
    guard isOpen else {
      return
    }
    suggestions.setSuggestions(newSuggestions)
    view.listContentHeight = suggestions.contentHeight
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

  // MARK: Closing

  func close() {
    view.hidePlaceholder()
    guard isOpen else {
      return
    }
    if let editor = field.currentEditor() {
      NotificationCenter.default.removeObserver(
        self, name: NSTextView.didChangeSelectionNotification, object: editor)
    }
    view.close()
    // Discards what the user typed, and the suggestions.
    actions?.omniboxDidBlur()
  }

  // MARK: Events

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

  /// Whether Return or a click on `part` opens something, which the omnibar
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
}

extension Omnibar: NSTextFieldDelegate {
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
      guard hasKeyword,
        textView.selectedRange() == NSRange(location: 0, length: 0)
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
      guard PaletteView.isReturn(NSApp.currentEvent) else {
        return false
      }
      submit(nil)
    default:
      return false
    }
    return true
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
