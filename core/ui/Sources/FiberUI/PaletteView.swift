import AppKit

/// A glass panel over the window, which it dims, with a search field above a
/// list: the omnibar's and the command palette's. Its owner fills in the list,
/// handles the field, and closes it.
@MainActor
final class PaletteView: NSView {
  private static let maxWidth: CGFloat = 640
  private static let sideMargin: CGFloat = 32
  /// The panel's top sits this far down the window, and at least `minTop`.
  private static let topFraction: CGFloat = 0.2
  private static let minTop: CGFloat = 72
  /// Space kept below the panel when there's more in the list than fits.
  private static let bottomMargin: CGFloat = 24
  private static let cornerRadius: CGFloat = 26
  private static let rimWidth: CGFloat = 6
  private static let fieldRowHeight: CGFloat = 56
  private static let footerHeight: CGFloat = 30
  /// Between a hint's action and its key, and after its key.
  private static let hintInnerSpacing: CGFloat = 6
  private static let hintSpacing: CGFloat = 18
  static let horizontalInset: CGFloat = 18

  let field = NSTextField()
  /// Shown between the field's icon and the field, like the omnibar's keyword.
  var fieldAccessory: NSView? {
    didSet { content.fieldRow.accessory = fieldAccessory }
  }
  /// The list's view, in a scroll view under the field. It's as wide as the
  /// panel and `listContentHeight` tall.
  var list: NSView? {
    get { scrollView.documentView }
    set { scrollView.documentView = newValue }
  }
  var listContentHeight: CGFloat = 0 {
    didSet {
      if listContentHeight != oldValue {
        layoutPanel()
      }
    }
  }
  /// The footer's keys, like ("Open", "↩").
  var hints: [(action: String, key: String)] = [] {
    didSet {
      updateHints()
      content.needsLayout = true
    }
  }
  /// Called when the user clicks outside the panel.
  var onDismiss: () -> Void = {}
  private(set) var isOpen = false
  /// While set, the panel doesn't show even when open, though its field takes
  /// the keyboard; once cleared, an open panel fades in.
  var isHeld = false {
    didSet {
      if !isHeld && isOpen {
        fadeIn()
      }
    }
  }

  private let shadowView = OutsetShadowView()
  private let panel = RimmedGlassView(rimWidth: PaletteView.rimWidth)
  private let content: PaletteContentView
  private let scrollView = NSScrollView()
  private let hintsView = NSStackView()

  init(placeholder: String) {
    let icon = NSImageView(
      image: NSImage(
        systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
    icon.symbolConfiguration = .init(pointSize: 17, weight: .medium)
    icon.contentTintColor = .secondaryLabelColor
    content = PaletteContentView(
      fieldRow: FieldRowView(
        icon: icon, field: field, inset: Self.horizontalInset),
      list: scrollView, hints: hintsView, fieldRowHeight: Self.fieldRowHeight,
      footerHeight: Self.footerHeight, horizontalInset: Self.horizontalInset)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
    isHidden = true
    alphaValue = 0

    field.isBezeled = false
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingTail
    field.cell?.isScrollable = true
    field.font = .systemFont(ofSize: 20)
    field.placeholderAttributedString = NSAttributedString(
      string: placeholder,
      attributes: [
        .font: NSFont.systemFont(ofSize: 20),
        .foregroundColor: NSColor.tertiaryLabelColor,
      ])
    field.cell?.sendsActionOnEndEditing = false

    hintsView.spacing = Self.hintInnerSpacing

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay

    shadowView.cornerRadius = Self.cornerRadius
    addSubview(shadowView)
    panel.cornerRadius = Self.cornerRadius
    panel.contentView = content
    addSubview(panel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Fades the panel in (unless it's held), with the field focused.
  func open() {
    guard !isOpen else {
      return
    }
    isOpen = true
    layoutPanel()
    isHidden = false
    if !isHeld {
      fadeIn()
    }
    window?.makeFirstResponder(field)
  }

  private func fadeIn() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      animator().alphaValue = 1
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

  func fieldAccessoryDidResize() {
    content.fieldRow.needsLayout = true
  }

  // MARK: Layout

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    layoutPanel()
  }

  /// The panel, sized to show the list, as much as fits.
  private func layoutPanel() {
    let width = min(Self.maxWidth, bounds.width - 2 * Self.sideMargin)
    let top = max((bounds.height * Self.topFraction).rounded(), Self.minTop)
    let fixedHeight =
      2 * Self.rimWidth + Self.fieldRowHeight + 1 + Self.footerHeight
    let availableHeight = max(
      bounds.height - top - Self.bottomMargin - fixedHeight, 0)
    let listHeight = min(listContentHeight, availableHeight)
    content.listHeight = listHeight
    let height = fixedHeight + listHeight
    panel.frame = NSRect(
      x: ((bounds.width - width) / 2).rounded(),
      y: bounds.height - top - height,
      width: width, height: height)
    shadowView.frame = panel.frame
    list?.frame.size = NSSize(
      width: width - 2 * Self.rimWidth, height: listContentHeight)
    // Now, so the list can scroll to its selection within its new height.
    panel.layoutSubtreeIfNeeded()
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

  /// Whether `event` is Return, or the keypad's Enter, with any modifiers.
  static func isReturn(_ event: NSEvent?) -> Bool {
    guard let event, event.type == .keyDown else {
      return false
    }
    return ["\r", "\u{3}"].contains(event.charactersIgnoringModifiers)
  }

  /// A label for each color, so each is vibrant. AppKit won't make a label
  /// with several vibrant, and on glass one can then draw its label colors as
  /// flat grays, the faint ones darker than the glass.
  private func updateHints() {
    func label(_ string: String, weight: NSFont.Weight, color: NSColor)
      -> NSTextField
    {
      let label = NSTextField(labelWithString: string)
      label.font = .systemFont(ofSize: 11, weight: weight)
      label.textColor = color
      return label
    }
    for view in hintsView.arrangedSubviews {
      view.removeFromSuperview()
    }
    for (action, key) in hints {
      let keyLabel = label(key, weight: .medium, color: .tertiaryLabelColor)
      hintsView.addArrangedSubview(
        label(action, weight: .regular, color: .secondaryLabelColor))
      hintsView.addArrangedSubview(keyLabel)
      hintsView.setCustomSpacing(Self.hintSpacing, after: keyLabel)
    }
  }
}

private final class PaletteContentView: NSView {
  let fieldRow: FieldRowView
  var listHeight: CGFloat = 0 {
    didSet { needsLayout = true }
  }

  private let list: NSView
  private let hints: NSView
  private let fieldRowHeight: CGFloat
  private let footerHeight: CGFloat
  private let horizontalInset: CGFloat
  private let separator = NSBox()

  init(
    fieldRow: FieldRowView, list: NSView, hints: NSView,
    fieldRowHeight: CGFloat, footerHeight: CGFloat, horizontalInset: CGFloat
  ) {
    self.fieldRow = fieldRow
    self.list = list
    self.hints = hints
    self.fieldRowHeight = fieldRowHeight
    self.footerHeight = footerHeight
    self.horizontalInset = horizontalInset
    super.init(frame: .zero)
    separator.boxType = .separator
    for view in [fieldRow, separator, list, hints] {
      addSubview(view)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    fieldRow.frame = NSRect(
      x: 0, y: 0, width: bounds.width, height: fieldRowHeight)
    separator.frame = NSRect(
      x: 0, y: fieldRowHeight, width: bounds.width, height: 1)
    list.frame = NSRect(
      x: 0, y: fieldRowHeight + 1, width: bounds.width, height: listHeight)
    let size = hints.fittingSize
    hints.frame = NSRect(
      x: bounds.width - horizontalInset - size.width,
      y: bounds.height - footerHeight
        + ((footerHeight - size.height) / 2)
        .rounded(),
      width: size.width, height: size.height)
  }

  override func layout() {
    super.layout()
    resizeSubviews(withOldSize: bounds.size)
  }
}

private final class FieldRowView: NSView {
  private static let iconSpacing: CGFloat = 12
  private static let accessorySpacing: CGFloat = 8

  var accessory: NSView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let accessory {
        addSubview(accessory)
      }
      needsLayout = true
    }
  }

  private let icon: NSView
  private let field: NSView
  private let inset: CGFloat

  init(icon: NSView, field: NSView, inset: CGFloat) {
    self.icon = icon
    self.field = field
    self.inset = inset
    super.init(frame: .zero)
    addSubview(icon)
    addSubview(field)
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
    if let accessory, !accessory.isHidden {
      place(
        accessory, width: accessory.fittingSize.width,
        spacing: Self.accessorySpacing)
    }
    place(field, width: max(bounds.width - inset - x, 0), spacing: 0)
  }

  override func layout() {
    super.layout()
    resizeSubviews(withOldSize: bounds.size)
  }
}
