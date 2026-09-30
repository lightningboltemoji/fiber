import AppKit
import FiberBridge

/// The omnibar's suggestions. The browser moves the selection (see
/// `setSelection(index:part:actionIndex:)`). Indexes are the browser's too:
/// hidden suggestions keep their index but get no row.
@MainActor
final class SuggestionList: NSView {
  static let rowHeight: CGFloat = 38
  static let headerHeight: CGFloat = 26
  /// Space above the first row and below the last.
  static let verticalPadding: CGFloat = 6
  /// The rows' inset from the panel's sides.
  static let horizontalInset: CGFloat = 6

  /// The event's modifier keys decide where the page opens.
  var onOpen: (_ index: Int, _ part: FiberSuggestionPart, _ actionIndex: Int,
    _ event: NSEvent?) -> Void = { _, _, _, _ in }
  var onRemove: (_ index: Int) -> Void = { _ in }

  private var rows: [SuggestionRow] = []
  private var headers: [NSTextField] = []
  private(set) var contentHeight: CGFloat = 0

  var isEmpty: Bool { rows.isEmpty }
  var selectedRemovableIndex: Int? {
    rows.first { $0.index == selectedIndex && $0.isRemovable }?.index
  }
  private var selectedIndex = -1

  override var isFlipped: Bool { true }

  func setSuggestions(_ suggestions: [FiberSuggestion]) {
    for view in rows as [NSView] + headers {
      view.removeFromSuperview()
    }
    rows = []
    headers = []
    var y = Self.verticalPadding
    for (index, suggestion) in suggestions.enumerated()
    where !suggestion.isHidden {
      if !suggestion.header.isEmpty {
        let header = Self.makeHeader(suggestion.header)
        header.frame = NSRect(
          x: Self.horizontalInset + SuggestionRow.leadingPadding, y: y,
          width: 0, height: Self.headerHeight)
        addSubview(header)
        headers.append(header)
        y += Self.headerHeight
      }
      let row = SuggestionRow(suggestion: suggestion, index: index)
      row.frame = NSRect(x: 0, y: y, width: 0, height: Self.rowHeight)
      row.onOpen = { [weak self] part, actionIndex, event in
        self?.onOpen(index, part, actionIndex, event)
      }
      row.onRemove = { [weak self] in self?.onRemove(index) }
      addSubview(row)
      rows.append(row)
      y += Self.rowHeight
    }
    contentHeight = rows.isEmpty ? 0 : y + Self.verticalPadding
    needsLayout = true
    updateHover()
  }

  /// Highlights suggestion `index` (-1 for none) and, within it, `part`.
  func setSelection(
    index: Int, part: FiberSuggestionPart, actionIndex: Int
  ) {
    selectedIndex = index
    for row in rows {
      row.setSelection(
        row.index == index ? part : nil, actionIndex: actionIndex)
    }
    if let row = rows.first(where: { $0.index == index }) {
      // Within the scroll view, when there are more rows than fit.
      scrollToVisible(row.frame.insetBy(dx: 0, dy: -Self.verticalPadding))
    }
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    for row in rows {
      row.frame = NSRect(
        x: Self.horizontalInset, y: row.frame.minY,
        width: bounds.width - 2 * Self.horizontalInset, height: Self.rowHeight)
    }
    for header in headers {
      header.frame.size.width =
        bounds.width - header.frame.minX - Self.horizontalInset
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

  private static func makeHeader(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    label.cell?.usesSingleLineMode = true
    return label
  }
}

/// One suggestion, with a button for each of its parts: keyword search,
/// actions like Switch to Tab, and removing it.
@MainActor
private final class SuggestionRow: NSView {
  static let leadingPadding: CGFloat = 12
  private static let iconSize: CGFloat = 16
  private static let cornerRadius: CGFloat = 12

  let index: Int
  var onOpen: (FiberSuggestionPart, Int, NSEvent?) -> Void = { _, _, _ in }
  var onRemove: () -> Void = {}
  var isHovered = false {
    didSet {
      if isHovered != oldValue {
        updateAppearance()
      }
    }
  }

  private let suggestion: FiberSuggestion
  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private let accessories = NSStackView()
  private var keywordPill: SuggestionPill?
  private var actionPills: [SuggestionPill] = []
  private let removeButton = NSButton()
  private var selectedPart: FiberSuggestionPart?
  private var selectedActionIndex = 0
  private var isSelectable: Bool { suggestion.kind != .message }
  var isRemovable: Bool { suggestion.isRemovable }

  init(suggestion: FiberSuggestion, index: Int) {
    self.suggestion = suggestion
    self.index = index
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.cornerCurve = .continuous

    icon.imageScaling = .scaleProportionallyDown
    label.lineBreakMode = .byTruncatingTail
    label.cell?.usesSingleLineMode = true
    label.setContentCompressionResistancePriority(
      .defaultLow, for: .horizontal)

    accessories.orientation = .horizontal
    accessories.spacing = 6
    if !suggestion.keywordLabel.isEmpty {
      let pill = SuggestionPill(title: suggestion.keywordLabel, key: "⇥")
      pill.onClick = { [weak self] event in
        self?.onOpen(.keyword, 0, event)
      }
      keywordPill = pill
      accessories.addArrangedSubview(pill)
    }
    for (actionIndex, title) in suggestion.actionTitles.enumerated() {
      let pill = SuggestionPill(title: title, key: nil)
      pill.onClick = { [weak self] event in
        self?.onOpen(.action, actionIndex, event)
      }
      actionPills.append(pill)
      accessories.addArrangedSubview(pill)
    }
    if suggestion.isRemovable {
      removeButton.image = NSImage(
        systemSymbolName: "xmark", accessibilityDescription: "Remove")
      removeButton.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
      removeButton.isBordered = false
      removeButton.refusesFirstResponder = true
      removeButton.toolTip = "Remove Suggestion"
      removeButton.target = self
      removeButton.action = #selector(remove(_:))
      removeButton.wantsLayer = true
      removeButton.layer?.cornerRadius = 10
      accessories.addArrangedSubview(removeButton)
      NSLayoutConstraint.activate([
        removeButton.widthAnchor.constraint(equalToConstant: 20),
        removeButton.heightAnchor.constraint(equalToConstant: 20),
      ])
    }

    for view in [icon, label, accessories] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Self.leadingPadding),
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
      icon.heightAnchor.constraint(equalToConstant: Self.iconSize),
      label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      accessories.leadingAnchor.constraint(
        greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
      accessories.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -9),
      accessories.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    setAccessibilityElement(true)
    setAccessibilityRole(isSelectable ? .button : .staticText)
    setAccessibilityLabel(
      [suggestion.contents, suggestion.detail].filter { !$0.isEmpty }
        .joined(separator: ", "))
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func setSelection(_ part: FiberSuggestionPart?, actionIndex: Int) {
    guard part != selectedPart || actionIndex != selectedActionIndex else {
      return
    }
    selectedPart = part
    selectedActionIndex = actionIndex
    updateAppearance()
  }

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

  // Opens on release, inside the row, as Chrome's popup does.
  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    open(with: event)
  }

  // A middle click opens in a new tab.
  override func otherMouseDown(with event: NSEvent) {}

  override func otherMouseUp(with event: NSEvent) {
    open(with: event)
  }

  override func accessibilityPerformPress() -> Bool {
    guard isSelectable else {
      return false
    }
    onOpen(.row, 0, nil)
    return true
  }

  private func open(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if isSelectable, bounds.contains(point) {
      onOpen(.row, 0, event)
    }
  }

  @objc private func remove(_ sender: Any?) {
    onRemove()
  }

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
    let isRowSelected = selectedPart == .row && isSelectable
    let background: NSColor? =
      isRowSelected
      ? .controlAccentColor
      : (selectedPart != nil || isHovered) && isSelectable
        ? .labelColor.withAlphaComponent(0.07) : nil
    layer?.backgroundColor = background?.cgColor

    let symbolColor: NSColor =
      isRowSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    if let favicon = suggestion.favicon {
      icon.image = favicon
      icon.contentTintColor = favicon.isTemplate ? symbolColor : nil
    } else {
      icon.image = NSImage(
        systemSymbolName: Self.symbolName(for: suggestion.kind),
        accessibilityDescription: nil)
      icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)
      icon.contentTintColor = symbolColor
    }

    label.attributedStringValue = text(selected: isRowSelected)

    keywordPill?.setHighlighted(
      selectedPart == .keyword, onSelectedRow: isRowSelected)
    for (actionIndex, pill) in actionPills.enumerated() {
      pill.setHighlighted(
        selectedPart == .action && selectedActionIndex == actionIndex,
        onSelectedRow: isRowSelected)
    }
    // Shown where it's relevant, so it doesn't clutter every history row.
    removeButton.isHidden = !(isHovered || selectedPart != nil)
    removeButton.contentTintColor =
      selectedPart == .remove
      ? .alternateSelectedControlTextColor
      : isRowSelected
        ? .alternateSelectedControlTextColor.withAlphaComponent(0.8)
        : .secondaryLabelColor
    removeButton.layer?.backgroundColor =
      selectedPart == .remove ? NSColor.controlAccentColor.cgColor : nil
  }

  /// The contents, then the detail, each styled by its runs: matches with
  /// what the user typed in a heavier weight, dim parts fainter.
  private func text(selected: Bool) -> NSAttributedString {
    let text = NSMutableAttributedString()
    let isMessage = suggestion.kind == .message
    text.append(
      Self.styled(
        suggestion.contents, runs: suggestion.contentsRuns, size: 14,
        color: selected
          ? .alternateSelectedControlTextColor
          : isMessage ? .secondaryLabelColor : .labelColor,
        selected: selected))
    if !suggestion.detail.isEmpty {
      let detailColor: NSColor =
        selected
        ? .alternateSelectedControlTextColor.withAlphaComponent(0.75)
        : .secondaryLabelColor
      if !suggestion.contents.isEmpty {
        text.append(
          NSAttributedString(
            string: "  —  ",
            attributes: [
              .font: NSFont.systemFont(ofSize: 13),
              .foregroundColor: detailColor.withAlphaComponent(0.5),
            ]))
      }
      text.append(
        Self.styled(
          suggestion.detail, runs: suggestion.detailRuns, size: 13,
          color: detailColor, selected: selected))
    }
    return text
  }

  private static func styled(
    _ string: String, runs: [FiberTextRun], size: CGFloat, color: NSColor,
    selected: Bool
  ) -> NSAttributedString {
    let text = NSMutableAttributedString(
      string: string,
      attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
    let length = (string as NSString).length
    for run in runs {
      guard NSMaxRange(run.range) <= length else {
        continue
      }
      if run.style.contains(.match) {
        text.addAttribute(
          .font, value: NSFont.systemFont(ofSize: size, weight: .semibold),
          range: run.range)
      }
      if run.style.contains(.dim), !selected {
        text.addAttribute(
          .foregroundColor, value: NSColor.tertiaryLabelColor, range: run.range)
      }
    }
    return text
  }

  private static func symbolName(for kind: FiberSuggestionKind) -> String {
    switch kind {
    case .page: "globe"
    case .bookmark: "star"
    case .search: "magnifyingglass"
    case .searchHistory: "clock.arrow.circlepath"
    case .trendingSearch: "chart.line.uptrend.xyaxis"
    case .calculator: "equal"
    case .extension: "puzzlepiece.extension"
    case .action: "gearshape"
    case .message: "info.circle"
    @unknown default: "globe"
    }
  }
}

/// A button on a suggestion's row for one of its parts, like "Search YouTube"
/// or "Switch to this tab": a capsule that fills in when the part is selected
/// (with Tab).
@MainActor
private final class SuggestionPill: NSView {
  private static let height: CGFloat = 24

  var onClick: (NSEvent?) -> Void = { _ in }

  private let title: String
  private let key: String?
  private let label = NSTextField(labelWithString: "")
  private var isHighlighted = false
  private var isOnSelectedRow = false

  init(title: String, key: String?) {
    self.title = title
    self.key = key
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = Self.height / 2
    layer?.borderWidth = 1
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Self.height),
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(title)
    update()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func setHighlighted(_ highlighted: Bool, onSelectedRow: Bool) {
    isHighlighted = highlighted
    isOnSelectedRow = onSelectedRow
    update()
  }

  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      onClick(event)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    onClick(nil)
    return true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    update()
  }

  private func update() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      updateColors()
    }
  }

  private func updateColors() {
    let color: NSColor =
      isHighlighted || isOnSelectedRow
      ? .alternateSelectedControlTextColor : .secondaryLabelColor
    layer?.backgroundColor =
      isHighlighted ? NSColor.controlAccentColor.cgColor : nil
    layer?.borderColor =
      isHighlighted
      ? NSColor.clear.cgColor : color.withAlphaComponent(0.35).cgColor
    let text = NSMutableAttributedString(
      string: title,
      attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: color,
      ])
    if let key {
      text.append(
        NSAttributedString(
          string: "  \(key)",
          attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color.withAlphaComponent(0.6),
          ]))
    }
    label.attributedStringValue = text
  }
}
