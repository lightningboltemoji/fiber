import AppKit

/// The command palette's rows: tabs and commands, then tabs found by their
/// pages' text, under a heading. The palette moves the selection.
@MainActor
final class PaletteResultList: NSView {
  private static let headerHeight: CGFloat = 28
  private static let messageHeight: CGFloat = 40
  /// Space above the first row and below the last.
  private static let verticalPadding: CGFloat = 6
  /// The rows' inset from the panel's sides.
  private static let horizontalInset: CGFloat = 6

  var onOpen: (Int) -> Void = { _ in }
  private(set) var contentHeight: CGFloat = 0

  private var rows: [PaletteRow] = []
  private var labels: [NSTextField] = []

  override var isFlipped: Bool { true }

  /// Lists `items`, with the page text heading before `pageTextStart`, or
  /// `message` when there are none.
  func setItems(_ items: [PaletteItem], pageTextStart: Int?, message: String?) {
    for view in rows as [NSView] + labels {
      view.removeFromSuperview()
    }
    rows = []
    labels = []
    var y = Self.verticalPadding
    /// Puts `label` in a band `height` tall: `bottomInset` from its bottom,
    /// or without one, centered.
    func addLabel(_ label: NSTextField, height: CGFloat, bottomInset: CGFloat?)
    {
      let labelHeight = label.fittingSize.height
      let labelY =
        bottomInset.map { y + height - labelHeight - $0 }
        ?? y + ((height - labelHeight) / 2).rounded()
      label.frame = NSRect(
        x: Self.horizontalInset + PaletteRow.leadingPadding, y: labelY,
        width: 0, height: labelHeight)
      addSubview(label)
      labels.append(label)
      y += height
    }
    for (index, item) in items.enumerated() {
      if index == pageTextStart {
        let header = NSTextField(labelWithString: "Found in pages")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        addLabel(header, height: Self.headerHeight, bottomInset: 4)
      }
      let row = PaletteRow(item: item)
      row.frame = NSRect(x: 0, y: y, width: 0, height: row.height)
      row.onOpen = { [weak self] in self?.onOpen(index) }
      addSubview(row)
      rows.append(row)
      y += row.height
    }
    if let message {
      let label = NSTextField(labelWithString: message)
      label.font = .systemFont(ofSize: 13)
      label.textColor = .secondaryLabelColor
      addLabel(label, height: Self.messageHeight, bottomInset: nil)
    }
    contentHeight = y == Self.verticalPadding ? 0 : y + Self.verticalPadding
    needsLayout = true
    updateHover()
  }

  /// Highlights row `index`, and scrolls to it.
  func setSelection(_ index: Int?) {
    for (rowIndex, row) in rows.enumerated() {
      row.isSelected = rowIndex == index
    }
    if let index, rows.indices.contains(index) {
      var frame = rows[index].frame.insetBy(dx: 0, dy: -Self.verticalPadding)
      // The heading above the first match in pages, with it.
      if index > 0, rows[index - 1].frame.maxY < rows[index].frame.minY {
        frame.origin.y -= Self.headerHeight
        frame.size.height += Self.headerHeight
      }
      scrollToVisible(frame)
    }
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    for row in rows {
      row.frame = NSRect(
        x: Self.horizontalInset, y: row.frame.minY,
        width: bounds.width - 2 * Self.horizontalInset, height: row.height)
    }
    for label in labels {
      label.frame.size.width =
        bounds.width - label.frame.minX - Self.horizontalInset
    }
  }

  override func layout() {
    super.layout()
    resizeSubviews(withOldSize: bounds.size)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateHover()
  }

  /// Highlights the row under the pointer. Rows track it themselves, but
  /// newly made ones don't know until it moves.
  private func updateHover() {
    guard let window else {
      return
    }
    let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
    for row in rows {
      row.isHovered = row.frame.contains(point)
    }
  }
}

/// One tab or command. A tab shows its title over its URL; one found in its
/// page, its title and URL over the words around the match; a command, its
/// name and shortcut.
@MainActor
private final class PaletteRow: NSView {
  static let leadingPadding: CGFloat = 12
  private static let trailingPadding: CGFloat = 12
  private static let iconSize: CGFloat = 20
  private static let iconSpacing: CGFloat = 12
  private static let cornerRadius: CGFloat = 12
  private static let titleSize: CGFloat = 14
  private static let detailSize: CGFloat = 12
  private static let snippetSize: CGFloat = 13

  let item: PaletteItem
  var onOpen: () -> Void = {}
  var isHovered = false {
    didSet {
      if isHovered != oldValue {
        updateAppearance()
      }
    }
  }
  var isSelected = false {
    didSet {
      if isSelected != oldValue {
        updateAppearance()
      }
    }
  }

  var height: CGFloat {
    switch item.kind {
    case .tab: 50
    case .pageText: 72
    case .command: 40
    }
  }

  private let icon = PaletteIcon()
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let snippetLabel = NSTextField(wrappingLabelWithString: "")
  private let accessoryLabel = NSTextField(labelWithString: "")

  init(item: PaletteItem) {
    self.item = item
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.cornerCurve = .continuous

    for label in [titleLabel, subtitleLabel, accessoryLabel] {
      label.lineBreakMode = .byTruncatingTail
      label.cell?.usesSingleLineMode = true
    }
    snippetLabel.maximumNumberOfLines = 2
    snippetLabel.cell?.truncatesLastVisibleLine = true
    accessoryLabel.alignment = .right
    for view in [icon, titleLabel, subtitleLabel, snippetLabel, accessoryLabel]
    {
      addSubview(view)
    }
    subtitleLabel.isHidden = item.subtitle.isEmpty || isPageText
    snippetLabel.isHidden = !isPageText
    accessoryLabel.isHidden = item.accessory.isEmpty

    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(
      [item.title, item.subtitle, item.snippet, item.accessory]
        .filter { !$0.isEmpty }.joined(separator: ", "))
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  private var isPageText: Bool {
    if case .pageText = item.kind {
      return true
    }
    return false
  }

  override var isFlipped: Bool { true }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    let titleHeight: CGFloat = 18
    // A command's one line is centered; the rest start from the top.
    let titleY: CGFloat =
      if case .command = item.kind {
        ((bounds.height - titleHeight) / 2).rounded()
      } else {
        8
      }
    let iconY =
      if case .tab = item.kind {
        ((bounds.height - Self.iconSize) / 2).rounded()
      } else {
        titleY + ((titleHeight - Self.iconSize) / 2).rounded()
      }
    icon.frame = NSRect(
      x: Self.leadingPadding, y: iconY, width: Self.iconSize,
      height: Self.iconSize)

    let textX = Self.leadingPadding + Self.iconSize + Self.iconSpacing
    var textEnd = bounds.width - Self.trailingPadding
    if !accessoryLabel.isHidden {
      let width = accessoryLabel.fittingSize.width
      accessoryLabel.frame = NSRect(
        x: textEnd - width, y: titleY, width: width, height: titleHeight)
      textEnd -= width + 12
    }
    let textWidth = max(textEnd - textX, 0)
    titleLabel.frame = NSRect(
      x: textX, y: titleY, width: textWidth, height: titleHeight)
    subtitleLabel.frame = NSRect(
      x: textX, y: titleY + titleHeight + 1,
      width: max(bounds.width - Self.trailingPadding - textX, 0), height: 16)
    snippetLabel.frame = NSRect(
      x: textX, y: titleY + titleHeight + 2,
      width: max(bounds.width - Self.trailingPadding - textX, 0), height: 36)
    snippetLabel.preferredMaxLayoutWidth = snippetLabel.frame.width
  }

  override func layout() {
    super.layout()
    resizeSubviews(withOldSize: bounds.size)
  }

  // MARK: Mouse

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self))
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
  }

  // Opens on release, inside the row.
  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      onOpen()
    }
  }

  override func accessibilityPerformPress() -> Bool {
    onOpen()
    return true
  }

  // MARK: Appearance

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateAppearance()
  }

  private func updateAppearance() {
    // Resolves the layers' dynamic colors for light or dark.
    effectiveAppearance.performAsCurrentDrawingAppearance {
      updateColors()
    }
  }

  private func updateColors() {
    let background: NSColor? =
      isSelected
      ? .controlAccentColor
      : isHovered ? .labelColor.withAlphaComponent(0.07) : nil
    layer?.backgroundColor = background?.cgColor
    let primary: NSColor =
      isSelected ? .alternateSelectedControlTextColor : .labelColor
    let secondary: NSColor =
      isSelected
      ? .alternateSelectedControlTextColor.withAlphaComponent(0.75)
      : .secondaryLabelColor

    let title = Self.styled(
      item.title, ranges: item.titleRanges, size: Self.titleSize,
      color: primary, matchColor: primary)
    if isPageText, !item.subtitle.isEmpty {
      // Its URL beside its title, to leave room for the snippet.
      let line = NSMutableAttributedString(attributedString: title)
      line.append(
        NSAttributedString(
          string: "  ·  ",
          attributes: [
            .font: NSFont.systemFont(ofSize: Self.detailSize),
            .foregroundColor: secondary.withAlphaComponent(0.5),
          ]))
      line.append(
        Self.styled(
          item.subtitle, ranges: item.subtitleRanges, size: Self.detailSize,
          color: secondary, matchColor: secondary))
      titleLabel.attributedStringValue = line
    } else {
      titleLabel.attributedStringValue = title
    }
    subtitleLabel.attributedStringValue = Self.styled(
      item.subtitle, ranges: item.subtitleRanges, size: Self.detailSize,
      color: secondary, matchColor: secondary)
    snippetLabel.attributedStringValue = Self.styled(
      item.snippet, ranges: item.snippetRanges, size: Self.snippetSize,
      color: secondary, matchColor: primary)
    accessoryLabel.attributedStringValue = NSAttributedString(
      string: item.accessory,
      attributes: [
        .font: NSFont.systemFont(
          ofSize: 12, weight: item.symbolName == nil ? .regular : .medium),
        .foregroundColor: isSelected ? secondary : NSColor.tertiaryLabelColor,
      ])
    icon.show(item, selected: isSelected)
  }

  /// `string` with `ranges` (what matched) heavier, and in `matchColor`.
  private static func styled(
    _ string: String, ranges: [NSRange], size: CGFloat, color: NSColor,
    matchColor: NSColor
  ) -> NSAttributedString {
    let text = NSMutableAttributedString(
      string: string,
      attributes: [
        .font: NSFont.systemFont(ofSize: size), .foregroundColor: color,
      ])
    let length = (string as NSString).length
    for range in ranges where NSMaxRange(range) <= length {
      text.addAttributes(
        [
          .font: NSFont.systemFont(ofSize: size, weight: .semibold),
          .foregroundColor: matchColor,
        ], range: range)
    }
    return text
  }
}

/// A row's icon: a tab's favicon, with a magnifying glass when it was found by
/// its page's text, or a command's symbol on a tile.
@MainActor
private final class PaletteIcon: NSView {
  private static let faviconSize: CGFloat = 16
  private static let badgeSize: CGFloat = 12

  private let image = NSImageView()
  private let badge = NSImageView()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.cornerCurve = .continuous
    image.imageScaling = .scaleProportionallyDown
    badge.image = NSImage(
      systemSymbolName: "magnifyingglass.circle.fill",
      accessibilityDescription: nil)
    addSubview(image)
    addSubview(badge)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  func show(_ item: PaletteItem, selected: Bool) {
    let secondary: NSColor =
      selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    if let symbolName = item.symbolName {
      image.image = NSImage(
        systemSymbolName: symbolName, accessibilityDescription: nil)
      image.symbolConfiguration = .init(pointSize: 12, weight: .medium)
      image.contentTintColor = secondary
      layer?.backgroundColor =
        (selected
        ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.2)
        : NSColor.labelColor.withAlphaComponent(0.08)).cgColor
    } else if let favicon = item.favicon {
      image.image = favicon
      image.contentTintColor = nil
      layer?.backgroundColor = nil
    } else {
      image.image = NSImage(
        systemSymbolName: "globe", accessibilityDescription: nil)
      image.symbolConfiguration = .init(pointSize: 13, weight: .regular)
      image.contentTintColor = secondary
      layer?.backgroundColor = nil
    }
    if case .pageText = item.kind {
      badge.isHidden = false
      badge.symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: Self.badgeSize, weight: .bold
      ).applying(
        .init(
          paletteColors: selected
            ? [.controlAccentColor, .alternateSelectedControlTextColor]
            : [.white, .controlAccentColor]))
    } else {
      badge.isHidden = true
    }
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let isPageText = !badge.isHidden
    let size = layer?.backgroundColor == nil ? Self.faviconSize : bounds.width
    // Up and left of center, when the badge is on its corner.
    let offset: CGFloat = isPageText ? -2 : 0
    image.frame = NSRect(
      x: ((bounds.width - size) / 2).rounded() + offset,
      y: ((bounds.height - size) / 2).rounded() + offset, width: size,
      height: size)
    badge.frame = NSRect(
      x: bounds.width - Self.badgeSize + 2,
      y: bounds.height - Self.badgeSize + 2,
      width: Self.badgeSize, height: Self.badgeSize)
  }
}
