import AppKit
import FiberBridge

/// The extensions menu, in a popover from the toolbar's puzzle piece: every
/// extension, with a pin to keep its button in the toolbar, and a way to the
/// Extensions page.
@MainActor
final class ExtensionsMenu: NSObject, NSPopoverDelegate {
  var onRun: (String) -> Void = { _ in }
  var onPin: (String, Bool) -> Void = { _, _ in }
  var onMenu: (String, NSEvent, NSView) -> Void = { _, _, _ in }
  var onManage: () -> Void = {}
  /// Called once the menu has closed, however it closed.
  var onClose: () -> Void = {}

  private let popover = NSPopover()
  private let content = ExtensionsMenuView()

  init(extensions: [FiberExtensionState]) {
    super.init()
    content.owner = self
    content.setExtensions(extensions)
    let controller = NSViewController()
    controller.view = content
    popover.contentViewController = controller
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
  }

  func show(relativeTo rect: NSRect, of view: NSView) {
    popover.contentSize = content.fittingSize
    popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
  }

  func close() {
    popover.close()
  }

  func setExtensions(_ extensions: [FiberExtensionState]) {
    content.setExtensions(extensions)
    popover.contentSize = content.fittingSize
  }

  /// The extension's row, while the menu's open.
  func row(for extensionID: String) -> NSView? {
    content.row(for: extensionID)
  }

  func popoverDidClose(_ notification: Notification) {
    onClose()
  }
}

@MainActor
private final class ExtensionsMenuView: NSView {
  private static let width: CGFloat = 300
  private static let padding: CGFloat = 8

  weak var owner: ExtensionsMenu?
  private let stack = NSStackView()
  private var rows: [ExtensionsMenuRow] = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
      stack.bottomAnchor.constraint(
        equalTo: bottomAnchor, constant: -Self.padding),
      stack.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Self.padding),
      stack.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Self.padding),
      widthAnchor.constraint(equalToConstant: Self.width),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func row(for extensionID: String) -> NSView? {
    rows.first { $0.extensionID == extensionID }
  }

  func setExtensions(_ extensions: [FiberExtensionState]) {
    rows = extensions.map { state in
      let row =
        rows.first { $0.extensionID == state.extensionID }
        ?? ExtensionsMenuRow(extensionID: state.extensionID)
      row.update(state)
      row.onClick = { [weak self] in self?.owner?.onRun(state.extensionID) }
      row.onPin = { [weak self] pinned in
        self?.owner?.onPin(state.extensionID, pinned)
      }
      row.onMenu = { [weak self] event, view in
        self?.owner?.onMenu(state.extensionID, event, view)
      }
      return row
    }

    var views: [NSView] = [
      Self.makeLabel(
        "Extensions", font: .systemFont(ofSize: 13, weight: .semibold),
        color: .secondaryLabelColor, inset: true)
    ]
    if rows.isEmpty {
      views.append(
        Self.makeLabel(
          "No extensions are installed.", font: .systemFont(ofSize: 13),
          color: .tertiaryLabelColor, inset: true))
    }
    views += rows
    views.append(Self.makeSeparator())
    let manage = ExtensionsMenuRow(
      title: "Manage Extensions", symbol: "gearshape")
    manage.onClick = { [weak self] in self?.owner?.onManage() }
    views.append(manage)
    stack.setViews(views, in: .top)
    for view in views {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    layoutSubtreeIfNeeded()
  }

  private static func makeLabel(
    _ text: String, font: NSFont, color: NSColor, inset: Bool
  ) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    let box = NSView()
    label.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(
        equalTo: box.leadingAnchor, constant: ExtensionsMenuRow.inset),
      label.trailingAnchor.constraint(
        lessThanOrEqualTo: box.trailingAnchor,
        constant: -ExtensionsMenuRow.inset),
      label.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
      label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
    ])
    return box
  }

  private static func makeSeparator() -> NSView {
    let separator = NSBox()
    separator.boxType = .separator
    let box = NSView()
    separator.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(separator)
    NSLayoutConstraint.activate([
      separator.leadingAnchor.constraint(
        equalTo: box.leadingAnchor, constant: ExtensionsMenuRow.inset),
      separator.trailingAnchor.constraint(
        equalTo: box.trailingAnchor, constant: -ExtensionsMenuRow.inset),
      separator.centerYAnchor.constraint(equalTo: box.centerYAnchor),
      box.heightAnchor.constraint(equalToConstant: 9),
    ])
    return box
  }
}

/// A row in the extensions menu, for an extension or a command, highlighting
/// under the pointer like a menu item.
@MainActor
private final class ExtensionsMenuRow: NSView {
  static let inset: CGFloat = 8
  private static let height: CGFloat = 32
  private static let cornerRadius: CGFloat = 8

  let extensionID: String?
  var onClick: () -> Void = {}
  var onPin: (Bool) -> Void = { _ in }
  var onMenu: (NSEvent, NSView) -> Void = { _, _ in }

  private let iconView = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private let pinButton = NSButton()
  private var isPinned = false
  private var isHighlighted = false {
    didSet { needsDisplay = true }
  }

  init(extensionID: String) {
    self.extensionID = extensionID
    super.init(frame: .zero)
    configure()
  }

  init(title: String, symbol: String) {
    extensionID = nil
    super.init(frame: .zero)
    configure()
    label.stringValue = title
    iconView.image = NSImage(
      systemSymbolName: symbol, accessibilityDescription: nil)
    iconView.contentTintColor = .secondaryLabelColor
    pinButton.isHidden = true
    setAccessibilityLabel(title)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  private func configure() {
    setAccessibilityElement(true)
    setAccessibilityRole(.menuItem)
    iconView.imageScaling = .scaleProportionallyDown
    label.font = .systemFont(ofSize: 13)
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    pinButton.isBordered = false
    pinButton.imagePosition = .imageOnly
    pinButton.target = self
    pinButton.action = #selector(pinClicked(_:))

    for view in [iconView, label, pinButton] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Self.height),
      iconView.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Self.inset),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: ExtensionIcon.size),
      iconView.heightAnchor.constraint(equalToConstant: ExtensionIcon.size),
      label.leadingAnchor.constraint(
        equalTo: iconView.trailingAnchor, constant: 10),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      pinButton.leadingAnchor.constraint(
        greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
      pinButton.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Self.inset),
      pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      pinButton.widthAnchor.constraint(equalToConstant: 24),
      pinButton.heightAnchor.constraint(equalToConstant: 24),
    ])
  }

  func update(_ state: FiberExtensionState) {
    iconView.image = ExtensionIcon.image(state.icon)
    iconView.alphaValue = state.isEnabled ? 1 : ExtensionIcon.disabledAlpha
    label.stringValue = state.name
    toolTip = state.tooltip
    setAccessibilityLabel(state.name)
    isPinned = state.isPinned
    let pinLabel = isPinned ? "Unpin from Toolbar" : "Pin to Toolbar"
    pinButton.image = NSImage(
      systemSymbolName: isPinned ? "pin.fill" : "pin",
      accessibilityDescription: pinLabel)
    pinButton.contentTintColor =
      isPinned ? .controlAccentColor : .tertiaryLabelColor
    pinButton.toolTip = state.canTogglePin ? pinLabel : nil
    pinButton.isEnabled = state.canTogglePin
    // Only a pinned extension that can't be unpinned shows its pin anyway.
    pinButton.isHidden = !state.canTogglePin && !isPinned
  }

  @objc private func pinClicked(_ sender: NSButton) {
    onPin(!isPinned)
  }

  // MARK: Events

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self))
  }

  override func mouseEntered(with event: NSEvent) {
    isHighlighted = true
  }

  override func mouseExited(with event: NSEvent) {
    isHighlighted = false
  }

  override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.contains(.control) {
      rightMouseDown(with: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard !event.modifierFlags.contains(.control),
      bounds.contains(convert(event.locationInWindow, from: nil))
    else {
      return
    }
    onClick()
  }

  override func rightMouseDown(with event: NSEvent) {
    guard extensionID != nil else {
      return
    }
    onMenu(event, self)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard isHighlighted else {
      return
    }
    NSColor.labelColor.withAlphaComponent(0.08).setFill()
    NSBezierPath(
      roundedRect: bounds, xRadius: Self.cornerRadius,
      yRadius: Self.cornerRadius
    ).fill()
  }
}
