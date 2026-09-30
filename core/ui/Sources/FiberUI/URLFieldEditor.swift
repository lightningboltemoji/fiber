import AppKit

/// The omnibar's field editor. Option-clicking part of a URL selects it and the
/// rest, ready to replace ("abc" in reddit.com/r/abc/some/thread selects
/// "abc/some/thread"). Holding Option underlines what a click would select.
@MainActor
final class URLFieldEditor: NSTextView {
  private var underlinedRange: NSRange?

  /// With TextKit 1, whose temporary attributes can underline. TextKit 2's
  /// rendering attributes can't, and selected text hides them.
  convenience init() {
    self.init(usingTextLayoutManager: false)
  }

  // Overridden with the others so NSTextView's convenience initializers are
  // inherited.
  override init(frame: NSRect) {
    super.init(frame: frame)
  }

  override init(frame: NSRect, textContainer: NSTextContainer?) {
    super.init(frame: frame, textContainer: textContainer)
    isFieldEditor = true
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [
          .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow,
          .inVisibleRect,
        ],
        owner: self))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// The range from the start of the part of `text` at `index` to its end.
  /// Parts are separated by runs of `/`, `?`, `&` and `#`, and a separator
  /// belongs to the part after it. Text with spaces is a search: it has none.
  static func tailRange(in text: String, at index: Int) -> NSRange? {
    let text = text as NSString
    let separators = CharacterSet(charactersIn: "/?&#")
    guard index < text.length,
      text.rangeOfCharacter(from: .whitespacesAndNewlines).location
        == NSNotFound
    else {
      return nil
    }
    func isSeparator(_ i: Int) -> Bool {
      UnicodeScalar(text.character(at: i)).map(separators.contains) ?? false
    }
    var start = index
    while start < text.length, isSeparator(start) {
      start += 1
    }
    guard start < text.length else {
      return nil
    }
    while start > 0, !isSeparator(start - 1) {
      start -= 1
    }
    return NSRange(location: start, length: text.length - start)
  }

  // MARK: Events

  override func mouseDown(with event: NSEvent) {
    guard Self.isOptionOnly(event.modifierFlags),
      let range = tailRange(at: event.locationInWindow)
    else {
      super.mouseDown(with: event)
      return
    }
    setSelectedRange(range)
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    updateUnderline(at: event.locationInWindow, flags: event.modifierFlags)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    setUnderlinedRange(nil)
  }

  override func flagsChanged(with event: NSEvent) {
    super.flagsChanged(with: event)
    if let window {
      updateUnderline(
        at: window.mouseLocationOutsideOfEventStream,
        flags: event.modifierFlags)
    }
  }

  override func didChangeText() {
    super.didChangeText()
    // The edit may have moved what's underlined.
    removeUnderline()
    if let window {
      updateUnderline(
        at: window.mouseLocationOutsideOfEventStream,
        flags: NSEvent.modifierFlags)
    }
  }

  override func resignFirstResponder() -> Bool {
    removeUnderline()
    return super.resignFirstResponder()
  }

  // MARK: Underline

  private func updateUnderline(
    at location: NSPoint, flags: NSEvent.ModifierFlags
  ) {
    let point = convert(location, from: nil)
    setUnderlinedRange(
      Self.isOptionOnly(flags) && visibleRect.contains(point)
        ? tailRange(at: location) : nil)
  }

  private func setUnderlinedRange(_ range: NSRange?) {
    guard range != underlinedRange else {
      return
    }
    removeUnderline()
    if let range {
      layoutManager?.addTemporaryAttribute(
        .underlineStyle, value: NSUnderlineStyle.single.rawValue,
        forCharacterRange: range)
      underlinedRange = range
    }
  }

  private func removeUnderline() {
    underlinedRange = nil
    layoutManager?.removeTemporaryAttribute(
      .underlineStyle,
      forCharacterRange: NSRange(
        location: 0, length: (string as NSString).length))
  }

  /// The tail under `location`, in window coordinates, if it's over the text.
  private func tailRange(at location: NSPoint) -> NSRange? {
    guard let window else {
      return nil
    }
    let point = window.convertPoint(toScreen: location)
    let index = characterIndex(for: point)
    guard index != NSNotFound, index < (string as NSString).length else {
      return nil
    }
    // It's the nearest character, even with the pointer past the text.
    let character = firstRect(
      forCharacterRange: NSRange(location: index, length: 1),
      actualRange: nil)
    guard (character.minX..<character.maxX).contains(point.x) else {
      return nil
    }
    return Self.tailRange(in: string, at: index)
  }

  private static func isOptionOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
    flags.intersection([.shift, .control, .option, .command]) == .option
  }
}
