import AppKit

/// The address field, drawn as a borderless pill to sit on a capsule
/// background. While idle it shows a short, centered form of the page's URL
/// (usually just the host). Focusing it swaps in the full URL, and the first
/// click selects all of it.
final class LocationField: NSTextField {
  private var url = ""
  private var displayURL = ""

  override class var cellClass: AnyClass? {
    get { LocationFieldCell.self }
    set { super.cellClass = newValue }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    placeholderString = "Search or enter address"
    isBezeled = false
    isBordered = false
    drawsBackground = false
    isEditable = true
    isSelectable = true
    usesSingleLineMode = true
    alignment = .center
    cell?.isScrollable = true
    cell?.sendsActionOnEndEditing = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  var isEditing: Bool { currentEditor() != nil }

  /// Whether the text being edited differs from the current URL.
  var hasEdits: Bool { isEditing && currentEditor()?.string != url }

  /// Sets the page's full URL and its short display form. The visible text
  /// only changes once the user isn't editing.
  func setURL(_ url: String, displayURL: String) {
    self.url = url
    self.displayURL = displayURL
    if !isEditing {
      stringValue = displayURL
    }
  }

  /// While editing, discards the user's changes and selects the full URL.
  func revertEdits() {
    guard let editor = currentEditor() else {
      return
    }
    editor.string = url
    editor.selectAll(nil)
  }

  override func becomeFirstResponder() -> Bool {
    // Swap in the full URL before editing starts; super then selects it all.
    if !isEditing {
      alignment = .natural
      stringValue = url
    }
    return super.becomeFirstResponder()
  }

  override func mouseDown(with event: NSEvent) {
    // Like other browsers, the click that starts editing selects the whole URL
    // rather than placing the caret; later clicks behave normally.
    let wasEditing = isEditing
    super.mouseDown(with: event)
    if !wasEditing {
      currentEditor()?.selectAll(nil)
    }
  }

  override func textDidEndEditing(_ notification: Notification) {
    // Sends the action on Return, which may move focus to the page.
    super.textDidEndEditing(notification)
    if !isEditing {
      alignment = .center
      stringValue = displayURL
    }
  }
}

/// Draws the field as a pill: text inset from the rounded ends and centered
/// vertically, and a focus ring that follows the pill's outline. The pill's
/// background comes from the view the field is placed in.
private final class LocationFieldCell: NSTextFieldCell {
  private static let horizontalTextInset: CGFloat = 12

  // Set while super positions the field editor; it passes back the rect we
  // already adjusted.
  private var isSettingUpEditor = false

  override func drawingRect(forBounds bounds: NSRect) -> NSRect {
    var rect = super.drawingRect(forBounds: bounds)
    if isSettingUpEditor {
      return rect
    }
    rect = rect.insetBy(dx: Self.horizontalTextInset, dy: 0)
    let textHeight = cellSize(forBounds: rect).height
    if textHeight < rect.height {
      rect.origin.y += ((rect.height - textHeight) / 2).rounded(.down)
      rect.size.height = textHeight
    }
    return rect
  }

  override func edit(
    withFrame frame: NSRect, in controlView: NSView, editor: NSText,
    delegate: Any?, event: NSEvent?
  ) {
    let rect = drawingRect(forBounds: frame)
    isSettingUpEditor = true
    super.edit(
      withFrame: rect, in: controlView, editor: editor, delegate: delegate,
      event: event)
    isSettingUpEditor = false
  }

  override func select(
    withFrame frame: NSRect, in controlView: NSView, editor: NSText,
    delegate: Any?, start: Int, length: Int
  ) {
    let rect = drawingRect(forBounds: frame)
    isSettingUpEditor = true
    super.select(
      withFrame: rect, in: controlView, editor: editor, delegate: delegate,
      start: start, length: length)
    isSettingUpEditor = false
  }

  override func drawFocusRingMask(
    withFrame cellFrame: NSRect, in controlView: NSView
  ) {
    let radius = cellFrame.height / 2
    NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius)
      .fill()
  }

  override func focusRingMaskBounds(
    forFrame cellFrame: NSRect, in controlView: NSView
  ) -> NSRect {
    cellFrame
  }
}
