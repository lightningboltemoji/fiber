import AppKit

/// The omnibar's field editor. Option-clicking part of a URL selects it and the
/// rest, ready to replace ("abc" in reddit.com/r/abc/some/thread selects
/// "abc/some/thread"). Holding Option underlines what a click would select,
/// and numbers the parts after the host, which Option-1 to Option-9 select.
@MainActor
final class URLFieldEditor: NSTextView {
  /// Shows the numbers. The omnibar lays it over the field.
  let partNumbersView = PartNumbersView()
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

  private static let separators = CharacterSet(charactersIn: "/?&#")

  /// The range from the start of the part of `text` at `index` to its end.
  /// Parts are separated by runs of `/`, `?`, `&` and `#`, and a separator
  /// belongs to the part after it. Text with spaces is a search: it has none.
  static func tailRange(in text: String, at index: Int) -> NSRange? {
    let text = text as NSString
    guard index < text.length, !isSearch(text) else {
      return nil
    }
    var start = index
    while start < text.length, isSeparator(text, at: start) {
      start += 1
    }
    guard start < text.length else {
      return nil
    }
    while start > 0, !isSeparator(text, at: start - 1) {
      start -= 1
    }
    return NSRange(location: start, length: text.length - start)
  }

  /// The parts after the host, which Option-1 to Option-9 select with the
  /// rest. Text without a scheme starts with its host.
  static func numberedParts(in text: String) -> [NSRange] {
    let text = text as NSString
    guard !isSearch(text) else {
      return []
    }
    let scheme = text.range(
      of: "^[a-z][a-z0-9+.-]*://",
      options: [.regularExpression, .caseInsensitive])
    var index = scheme.location == NSNotFound ? 0 : NSMaxRange(scheme)
    while index < text.length, !isSeparator(text, at: index) {
      index += 1
    }
    var parts: [NSRange] = []
    while index < text.length, parts.count < 9 {
      while index < text.length, isSeparator(text, at: index) {
        index += 1
      }
      let start = index
      while index < text.length, !isSeparator(text, at: index) {
        index += 1
      }
      if index > start {
        parts.append(NSRange(location: start, length: index - start))
      }
    }
    return parts
  }

  private static func isSearch(_ text: NSString) -> Bool {
    text.rangeOfCharacter(from: .whitespacesAndNewlines).location != NSNotFound
  }

  private static func isSeparator(_ text: NSString, at index: Int) -> Bool {
    UnicodeScalar(text.character(at: index)).map(separators.contains) ?? false
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

  /// Text without numbered parts gets Option and a digit as typed (Option-2
  /// is ™).
  override func keyDown(with event: NSEvent) {
    guard Self.isOptionOnly(event.modifierFlags), !hasMarkedText(),
      let number = event.charactersIgnoringModifiers.flatMap({ Int($0) })
    else {
      super.keyDown(with: event)
      return
    }
    let parts = Self.numberedParts(in: string)
    if parts.isEmpty {
      super.keyDown(with: event)
    } else if parts.indices.contains(number - 1) {
      let start = parts[number - 1].location
      setSelectedRange(
        NSRange(location: start, length: (string as NSString).length - start))
      scrollRangeToVisible(NSRange(location: start, length: 0))
    } else {
      NSSound.beep()
    }
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
    updatePartNumbers(flags: event.modifierFlags)
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
    updatePartNumbers(flags: NSEvent.modifierFlags)
  }

  override func resignFirstResponder() -> Bool {
    removeUnderline()
    partNumbersView.isShown = false
    return super.resignFirstResponder()
  }

  /// The superview is the clip view the text scrolls in.
  override func viewWillMove(toSuperview newSuperview: NSView?) {
    super.viewWillMove(toSuperview: newSuperview)
    let center = NotificationCenter.default
    center.removeObserver(
      self, name: NSView.boundsDidChangeNotification, object: superview)
    if let newSuperview {
      newSuperview.postsBoundsChangedNotifications = true
      center.addObserver(
        self, selector: #selector(superviewBoundsDidChange(_:)),
        name: NSView.boundsDidChangeNotification, object: newSuperview)
    }
  }

  @objc private func superviewBoundsDidChange(_ notification: Notification) {
    updatePartNumbers(flags: NSEvent.modifierFlags)
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

  // MARK: Part numbers

  /// Numbers the parts in sight while Option alone is held.
  private func updatePartNumbers(flags: NSEvent.ModifierFlags) {
    guard Self.isOptionOnly(flags), let layoutManager, let textContainer,
      let superview
    else {
      partNumbersView.isShown = false
      return
    }
    let visible = convert(superview.bounds, from: superview)
    partNumbersView.parts = Self.numberedParts(in: string).map { part in
      let glyphs = layoutManager.glyphRange(
        forCharacterRange: part, actualCharacterRange: nil)
      let rect = layoutManager.boundingRect(
        forGlyphRange: glyphs, in: textContainer
      ).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
      let minX = max(rect.minX, visible.minX)
      let maxX = min(rect.maxX, visible.maxX)
      guard minX < maxX else {
        return nil
      }
      return partNumbersView.convert(
        NSRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height),
        from: self)
    }
    partNumbersView.isShown = true
  }

  private static func isOptionOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
    flags.intersection([.shift, .control, .option, .command]) == .option
  }
}

/// The numbers of a URL's parts, each centered under its part between lines
/// that span it.
@MainActor
final class PartNumbersView: NSView {
  /// Between a number and its lines.
  private static let lineGap: CGFloat = 3
  /// Shorter lines, beside a short part's number, would be specks.
  private static let minLineWidth: CGFloat = 3

  /// Each numbered part's span, in this view, or nil while it's out of sight.
  var parts: [NSRect?] = [] {
    didSet { updateLabels() }
  }
  /// Fades the numbers in or out, as the palette does. They fade out where
  /// they were.
  var isShown = false {
    didSet {
      guard isShown != oldValue else {
        return
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration =
          isShown ? PaletteView.fadeInDuration : PaletteView.fadeOutDuration
        animator().alphaValue = isShown ? 1 : 0
      }
    }
  }

  private var labels: [NSTextField] = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    alphaValue = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.tertiaryLabelColor.setFill()
    for (part, label) in zip(parts, labels) {
      guard let part else {
        continue
      }
      let y = label.frame.midY.rounded()
      let left = NSRect(
        x: part.minX, y: y,
        width: label.frame.minX - Self.lineGap - part.minX, height: 1)
      let right = NSRect(
        x: label.frame.maxX + Self.lineGap, y: y,
        width: part.maxX - label.frame.maxX - Self.lineGap, height: 1)
      for line in [left, right] where line.width >= Self.minLineWidth {
        line.fill()
      }
    }
  }

  private func updateLabels() {
    while labels.count < parts.count {
      let label = NSTextField(labelWithString: String(labels.count + 1))
      label.font = .systemFont(ofSize: 11, weight: .semibold)
      label.textColor = .secondaryLabelColor
      addSubview(label)
      labels.append(label)
    }
    for (index, label) in labels.enumerated() {
      guard parts.indices.contains(index), let part = parts[index] else {
        label.isHidden = true
        continue
      }
      let size = label.fittingSize
      label.frame = NSRect(
        x: (part.midX - size.width / 2).rounded(),
        y: part.minY - size.height, width: size.width, height: size.height)
      label.isHidden = false
    }
    needsDisplay = true
  }
}
