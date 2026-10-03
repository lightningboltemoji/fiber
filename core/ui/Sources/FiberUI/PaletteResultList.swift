import AppKit

/// The command palette's rows: tabs and commands, then tabs found by their
/// pages' text, under a heading. The palette moves the selection. Before the
/// user types it lists every tab, so only the rows in sight have views, which
/// are reused as the list scrolls and changes.
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

  private var items: [PaletteItem] = []
  /// Where each item's row goes, top to bottom.
  private var rowSpans: [Range<CGFloat>] = []
  private var selectedIndex: Int?
  /// The rows in sight, or nearly, by the index of the item each shows.
  private var rows: [Int: PaletteRow] = [:]
  /// Rows out of sight, hidden, for items that scroll into it.
  private var spareRows: [PaletteRow] = []
  private let header = NSTextField(labelWithString: "Found in pages")
  private let messageLabel = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    header.font = .systemFont(ofSize: 11, weight: .semibold)
    header.textColor = .secondaryLabelColor
    messageLabel.font = .systemFont(ofSize: 13)
    messageLabel.textColor = .secondaryLabelColor
    for label in [header, messageLabel] {
      label.isHidden = true
      addSubview(label)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  /// Lists `items`, with the page text heading before `pageTextStart`, or
  /// `message` when there are none.
  func setItems(_ items: [PaletteItem], pageTextStart: Int?, message: String?) {
    self.items = items
    rowSpans = []
    var y = Self.verticalPadding
    /// Puts `label` in a band `height` tall: `bottomInset` from its bottom,
    /// or without one, centered.
    func place(_ label: NSTextField, height: CGFloat, bottomInset: CGFloat?) {
      let labelHeight = label.fittingSize.height
      let labelY =
        bottomInset.map { y + height - labelHeight - $0 }
        ?? y + ((height - labelHeight) / 2).rounded()
      label.frame = NSRect(
        x: Self.horizontalInset + PaletteRow.leadingPadding, y: labelY,
        width: 0, height: labelHeight)
      fitWidth(label)
      label.isHidden = false
      y += height
    }
    header.isHidden = true
    for (index, item) in items.enumerated() {
      if index == pageTextStart {
        place(header, height: Self.headerHeight, bottomInset: 4)
      }
      let height = PaletteRow.height(for: item.kind)
      rowSpans.append(y..<y + height)
      y += height
    }
    messageLabel.isHidden = true
    if let message {
      messageLabel.stringValue = message
      place(messageLabel, height: Self.messageHeight, bottomInset: nil)
    }
    contentHeight = y == Self.verticalPadding ? 0 : y + Self.verticalPadding
    updateRows(showingNewItems: true)
  }

  /// Highlights row `index`, and scrolls to it.
  func setSelection(_ index: Int?) {
    if let old = selectedIndex {
      rows[old]?.isSelected = false
    }
    selectedIndex = index
    guard let index, items.indices.contains(index) else {
      return
    }
    rows[index]?.isSelected = true
    var frame = frameForRow(at: index).insetBy(dx: 0, dy: -Self.verticalPadding)
    // The heading above the first match in pages, with it.
    if index > 0, rowSpans[index - 1].upperBound < rowSpans[index].lowerBound {
      frame.origin.y -= Self.headerHeight
      frame.size.height += Self.headerHeight
    }
    scrollToVisible(frame)
  }

  private func frameForRow(at index: Int) -> NSRect {
    let span = rowSpans[index]
    return NSRect(
      x: Self.horizontalInset, y: span.lowerBound,
      width: bounds.width - 2 * Self.horizontalInset,
      height: span.upperBound - span.lowerBound)
  }

  /// Gives each item in or near sight a row, from the rows that left it.
  /// With `showingNewItems`, the rows kept show their items again too.
  private func updateRows(showingNewItems: Bool = false) {
    var visible = bounds
    if let clipView = superview as? NSClipView {
      visible = convert(clipView.bounds, from: clipView)
    }
    // Half a screen either way, so scrolling a little makes none.
    let wanted = visible.insetBy(dx: 0, dy: -visible.height / 2)
    let lower = rowSpans.partitioningIndex { $0.upperBound > wanted.minY }
    let upper = rowSpans.partitioningIndex { $0.lowerBound >= wanted.maxY }
    let range = lower..<max(lower, upper)
    for (index, row) in rows where !range.contains(index) {
      row.isHidden = true
      spareRows.append(row)
      rows[index] = nil
    }
    for index in range {
      let row: PaletteRow
      if let shown = rows[index] {
        row = shown
        if showingNewItems {
          row.show(items[index])
        }
      } else if let spare = spareRows.popLast() {
        row = spare
        row.show(items[index])
        row.isHidden = false
        rows[index] = row
      } else {
        row = makeRow(items[index])
        rows[index] = row
      }
      row.index = index
      row.isSelected = index == selectedIndex
      row.frame = frameForRow(at: index)
    }
    updateHover()
  }

  private func makeRow(_ item: PaletteItem) -> PaletteRow {
    let row = PaletteRow(item: item)
    row.onOpen = { [weak self, unowned row] in self?.onOpen(row.index) }
    addSubview(row)
    return row
  }

  /// Fits the heading or the message to the list's width.
  private func fitWidth(_ label: NSTextField) {
    label.frame.size.width = max(
      bounds.width - label.frame.minX - Self.horizontalInset, 0)
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    updateRows()
    fitWidth(header)
    fitWidth(messageLabel)
  }

  override func layout() {
    super.layout()
    resizeSubviews(withOldSize: bounds.size)
  }

  /// The superview is the clip view the list scrolls in: the rows in sight
  /// change as it scrolls or resizes.
  override func viewWillMove(toSuperview newSuperview: NSView?) {
    super.viewWillMove(toSuperview: newSuperview)
    let center = NotificationCenter.default
    let names = [
      NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification,
    ]
    for name in names {
      center.removeObserver(self, name: name, object: superview)
    }
    if let newSuperview {
      newSuperview.postsBoundsChangedNotifications = true
      newSuperview.postsFrameChangedNotifications = true
      for name in names {
        center.addObserver(
          self, selector: #selector(superviewDidChange(_:)), name: name,
          object: newSuperview)
      }
    }
  }

  @objc private func superviewDidChange(_ notification: Notification) {
    updateRows()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateHover()
  }

  /// Highlights the row under the pointer. Rows track it themselves, but
  /// newly shown ones don't know until it moves.
  private func updateHover() {
    guard let window else {
      return
    }
    let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
    for row in rows.values {
      row.isHovered = row.frame.contains(point)
    }
  }
}

extension Array {
  /// The index of the first element for which `isAfter` is true, in an array
  /// where it's false for those before it and true for the rest.
  fileprivate func partitioningIndex(where isAfter: (Element) -> Bool) -> Int {
    var low = 0
    var high = count
    while low < high {
      let middle = (low + high) / 2
      if isAfter(self[middle]) {
        high = middle
      } else {
        low = middle + 1
      }
    }
    return low
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

  private(set) var item: PaletteItem
  /// The index of its item in the list.
  var index = 0
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

  static func height(for kind: PaletteItem.Kind) -> CGFloat {
    switch kind {
    case .tab: 50
    case .pageText: 72
    case .command: 40
    }
  }

  private let icon = PaletteIcon()
  private let titleLabel = MixedColorLabel(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let snippetLabel = MixedColorLabel(wrappingLabelWithString: "")
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
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    showItem()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func show(_ item: PaletteItem) {
    guard item != self.item else {
      return
    }
    self.item = item
    showItem()
  }

  private func showItem() {
    subtitleLabel.isHidden = item.subtitle.isEmpty || isPageText
    snippetLabel.isHidden = !isPageText
    accessoryLabel.isHidden = item.accessory.isEmpty
    setAccessibilityLabel(
      [item.title, item.subtitle, item.snippet, item.accessory]
        .filter { !$0.isEmpty }.joined(separator: ", "))
    needsLayout = true
    updateAppearance()
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
    titleLabel.isOnSelectedRow = isSelected
    snippetLabel.isOnSelectedRow = isSelected
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
    let shown: NSImage
    if let symbolName = item.symbolName {
      shown = Self.symbol(symbolName, size: 12, weight: .medium)
      layer?.backgroundColor =
        (selected
        ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.2)
        : NSColor.labelColor.withAlphaComponent(0.08)).cgColor
    } else {
      shown = item.favicon ?? Self.symbol("globe", size: 13, weight: .regular)
      layer?.backgroundColor = nil
    }
    // Setting either redraws it.
    if image.image !== shown {
      image.image = shown
    }
    let tint = shown.isTemplate ? secondary : nil
    if image.contentTintColor != tint {
      image.contentTintColor = tint
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

  private static var symbols: [String: NSImage] = [:]

  private static func symbol(
    _ name: String, size: CGFloat, weight: NSFont.Weight
  ) -> NSImage {
    let key = "\(name) \(size) \(weight.rawValue)"
    if let symbol = symbols[key] {
      return symbol
    }
    let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
      .withSymbolConfiguration(.init(pointSize: size, weight: weight))!
    symbols[key] = symbol
    return symbol
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
