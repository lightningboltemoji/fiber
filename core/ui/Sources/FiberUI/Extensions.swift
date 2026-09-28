import AppKit
import FiberBridge

@objc @implementation extension FiberExtensionState {
  let extensionID: String
  let name: String
  let tooltip: String
  let icon: NSImage?
  let badgeText: String
  let badgeTextColor: NSColor?
  let badgeBackgroundColor: NSColor?
  let isEnabled: Bool
  let isPinned: Bool
  let canTogglePin: Bool

  init(
    extensionID: String, name: String, tooltip: String, icon: NSImage?,
    badgeText: String, badgeTextColor: NSColor?,
    badgeBackgroundColor: NSColor?, enabled: Bool, pinned: Bool,
    canTogglePin: Bool
  ) {
    self.extensionID = extensionID
    self.name = name
    self.tooltip = tooltip
    self.icon = icon
    self.badgeText = badgeText
    self.badgeTextColor = badgeTextColor
    self.badgeBackgroundColor = badgeBackgroundColor
    self.isEnabled = enabled
    self.isPinned = pinned
    self.canTogglePin = canTogglePin
    super.init()
  }
}

/// A window's extensions: the menu (ExtensionsMenu) from the toolbar's puzzle
/// piece, the pinned extensions' buttons (ExtensionsBar), and their popups
/// (ExtensionPopup), which open from the puzzle piece when unpinned.
@MainActor
final class ExtensionsController: NSObject, FiberExtensions {
  var actions: (any FiberExtensionsActions)?

  private let bar: ExtensionsBar
  private let isBarShown: () -> Bool
  /// Where the bar's menu button is, in the window's content view, for
  /// popups while the toolbar is hidden.
  private let hiddenMenuButtonRect: () -> (NSView, NSRect)?
  private var extensions: [FiberExtensionState] = []
  private var menu: ExtensionsMenu?
  private weak var popup: ExtensionPopup?
  /// The click that last closed a popover (see ToolbarButton), so the same
  /// click on its button doesn't open it again.
  private var closingClick: (button: String, timestamp: TimeInterval)?

  init(
    bar: ExtensionsBar, isBarShown: @escaping () -> Bool,
    hiddenMenuButtonRect: @escaping () -> (NSView, NSRect)?
  ) {
    self.bar = bar
    self.isBarShown = isBarShown
    self.hiddenMenuButtonRect = hiddenMenuButtonRect
    super.init()
    bar.menuButton.target = self
    bar.menuButton.action = #selector(menuButtonClicked(_:))
    bar.onClick = { [weak self] button in self?.buttonClicked(button) }
    bar.onMenu = { [weak self] event, button in
      self?.actions?.showMenuForExtension(
        withID: button.extensionID, event: event, view: button)
    }
  }

  // MARK: FiberExtensions

  func setExtensions(
    _ extensions: [FiberExtensionState], pinnedIDs: [String]
  ) {
    self.extensions = extensions
    let byID = Dictionary(
      extensions.map { ($0.extensionID, $0) }, uniquingKeysWith: { a, _ in a })
    bar.setPinned(pinnedIDs.compactMap { byID[$0] })
    menu?.setExtensions(extensions)
  }

  func toggleMenu() {
    if menu != nil {
      closeMenu()
    } else {
      openMenu()
    }
  }

  func closeMenu() {
    menu?.close()
  }

  func showMenuForExtension(withID extensionID: String) {
    let view: NSView =
      menu?.row(for: extensionID) ?? bar.button(for: extensionID)
      ?? bar.menuButton
    guard let window = view.window,
      let event = NSEvent.mouseEvent(
        with: .rightMouseDown,
        location: view.convert(NSPoint(x: 0, y: view.bounds.maxY), to: nil),
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1)
    else {
      return
    }
    actions?.showMenuForExtension(
      withID: extensionID, event: event, view: view)
  }

  func popupForExtension(
    withID extensionID: String, contentsView: NSView,
    actions: any FiberExtensionPopupActions
  ) -> any FiberExtensionPopup {
    popup?.close()
    let popup = ExtensionPopup(
      contentsView: contentsView, actions: actions,
      anchor: { [weak self] in self?.popupAnchor(for: extensionID) })
    popup.onUserClose = { [weak self] in
      self?.noteClosingClick(for: extensionID)
    }
    self.popup = popup
    return popup
  }

  func windowWillClose() {
    closeMenu()
  }

  // MARK: Private

  private func openMenu() {
    let menu = ExtensionsMenu(extensions: extensions)
    menu.onRun = { [weak self] id in
      self?.actions?.runExtension(withID: id, fromMenu: true)
    }
    menu.onPin = { [weak self] id, pinned in
      self?.actions?.setPinned(pinned, forExtensionWithID: id)
    }
    menu.onMenu = { [weak self] id, event, view in
      self?.actions?.showMenuForExtension(withID: id, event: event, view: view)
    }
    menu.onManage = { [weak self] in
      self?.closeMenu()
      self?.actions?.manageExtensions()
    }
    menu.onClose = { [weak self, weak menu] in
      guard let self, self.menu === menu else {
        return
      }
      self.menu = nil
      self.noteClosingClick(for: Self.menuButtonKey)
    }
    guard let (view, rect) = menuButtonAnchor() else {
      return
    }
    self.menu = menu
    menu.show(relativeTo: rect, of: view)
  }

  private static let menuButtonKey = ""

  @objc private func menuButtonClicked(_ sender: ToolbarButton) {
    if closedByThisClick(sender, key: Self.menuButtonKey) {
      return
    }
    toggleMenu()
  }

  private func buttonClicked(_ button: ExtensionButton) {
    if closedByThisClick(button, key: button.extensionID) {
      return
    }
    actions?.runExtension(withID: button.extensionID, fromMenu: false)
  }

  /// A popover that closes on a click outside it closes before the click
  /// reaches whatever was clicked; if that's the button that opened it, the
  /// click only closes it.
  private func noteClosingClick(for key: String) {
    guard let event = NSApp.currentEvent,
      event.type == .leftMouseDown || event.type == .rightMouseDown
    else {
      return
    }
    closingClick = (key, event.timestamp)
  }

  private func closedByThisClick(_ button: ToolbarButton, key: String) -> Bool
  {
    defer { closingClick = nil }
    return closingClick?.button == key
      && closingClick?.timestamp == button.mouseDownTimestamp
  }

  private func menuButtonAnchor() -> (NSView, NSRect)? {
    if isBarShown(), bar.window != nil {
      return (bar.menuButton, bar.menuButton.bounds)
    }
    return hiddenMenuButtonRect()
  }

  private func popupAnchor(for extensionID: String) -> (NSView, NSRect)? {
    if isBarShown(), let button = bar.button(for: extensionID),
      button.window != nil
    {
      return (button, button.bounds)
    }
    return menuButtonAnchor()
  }
}

/// A toolbar button that notes when it's pressed, so a click that closed its
/// popover doesn't open it again (see ExtensionsController).
class ToolbarButton: NSButton {
  private(set) var mouseDownTimestamp: TimeInterval = -1

  override func mouseDown(with event: NSEvent) {
    mouseDownTimestamp = event.timestamp
    super.mouseDown(with: event)
  }
}

/// The extensions' part of the toolbar: the buttons of the pinned extensions,
/// then the puzzle piece that opens the extensions menu.
@MainActor
final class ExtensionsBar: NSStackView {
  let menuButton = Toolbar.makeButton(
    symbol: "puzzlepiece.extension", label: "Extensions")
  /// Clicks and right-clicks (or Control-clicks) on an extension's button.
  var onClick: (ExtensionButton) -> Void = { _ in }
  var onMenu: (NSEvent, ExtensionButton) -> Void = { _, _ in }
  /// Called when pinning or unpinning changes the bar's width.
  var onResize: () -> Void = {}

  private var buttons: [ExtensionButton] = []

  init() {
    super.init(frame: .zero)
    orientation = .horizontal
    spacing = 2
    addArrangedSubview(menuButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func button(for extensionID: String) -> ExtensionButton? {
    buttons.first { $0.extensionID == extensionID }
  }

  /// Shows `extensions`' buttons, in order, before the menu button. Buttons
  /// that stay are kept, so a popup from one stays put.
  func setPinned(_ extensions: [FiberExtensionState]) {
    let old = buttons
    buttons = extensions.map { state in
      let button =
        old.first { $0.extensionID == state.extensionID }
        ?? ExtensionButton(extensionID: state.extensionID)
      button.update(state)
      button.target = self
      button.action = #selector(buttonClicked(_:))
      button.onMenu = { [weak self] event, button in
        self?.onMenu(event, button)
      }
      return button
    }
    let changed = old.map(\.extensionID) != buttons.map(\.extensionID)
    guard changed else {
      return
    }
    setViews(buttons + [menuButton], in: .leading)
    onResize()
  }

  @objc private func buttonClicked(_ sender: ExtensionButton) {
    onClick(sender)
  }
}

@MainActor
final class ExtensionButton: ToolbarButton {
  let extensionID: String
  var onMenu: (NSEvent, ExtensionButton) -> Void = { _, _ in }
  private let badge = ExtensionBadge()

  init(extensionID: String) {
    self.extensionID = extensionID
    super.init(frame: .zero)
    imagePosition = .imageOnly
    imageScaling = .scaleProportionallyDown
    bezelStyle = .accessoryBarAction
    borderShape = .circle
    showsBorderOnlyWhileMouseInside = true
    widthAnchor.constraint(equalToConstant: Toolbar.buttonSize).isActive = true
    heightAnchor.constraint(equalToConstant: Toolbar.buttonSize).isActive = true
    badge.translatesAutoresizingMaskIntoConstraints = false
    addSubview(badge)
    NSLayoutConstraint.activate([
      badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
      badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func update(_ state: FiberExtensionState) {
    image = ExtensionIcon.image(state.icon)
    toolTip = state.tooltip
    setAccessibilityLabel(state.name)
    badge.set(
      text: state.badgeText, textColor: state.badgeTextColor,
      backgroundColor: state.badgeBackgroundColor)
    alphaValue = state.isEnabled ? 1 : ExtensionIcon.disabledAlpha
  }

  override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.contains(.control) {
      onMenu(event, self)
      return
    }
    super.mouseDown(with: event)
  }

  override func rightMouseDown(with event: NSEvent) {
    onMenu(event, self)
  }
}

enum ExtensionIcon {
  static let size: CGFloat = 16
  /// For an extension that can't do anything on the page.
  static let disabledAlpha: CGFloat = 0.45

  /// `icon`, or a stand-in while it loads.
  @MainActor
  static func image(_ icon: NSImage?) -> NSImage? {
    if let icon {
      return icon
    }
    return NSImage(
      systemSymbolName: "puzzlepiece.extension",
      accessibilityDescription: nil)
  }
}

/// An extension's badge: a few characters in a capsule, like a count.
@MainActor
final class ExtensionBadge: NSView {
  private static let height: CGFloat = 12
  private static let padding: CGFloat = 3
  private static let font = NSFont.systemFont(ofSize: 9, weight: .bold)
  /// Chrome's defaults are a theme color and whichever of black or white
  /// shows against the background.
  private static let defaultBackground = NSColor(
    srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1)

  private var text = ""
  private var textColor = NSColor.white
  private var backgroundColor = ExtensionBadge.defaultBackground

  func set(text: String, textColor: NSColor?, backgroundColor: NSColor?) {
    self.text = text
    let background =
      backgroundColor.flatMap { $0.alphaComponent > 0 ? $0 : nil }
      ?? Self.defaultBackground
    self.backgroundColor = background
    self.textColor =
      textColor.flatMap { $0.alphaComponent > 0 ? $0 : nil }
      ?? Self.contrastingText(on: background)
    isHidden = text.isEmpty
    invalidateIntrinsicContentSize()
    needsDisplay = true
  }

  override var intrinsicContentSize: NSSize {
    let width = attributedText.size().width + 2 * Self.padding
    return NSSize(
      width: max(ceil(width), Self.height), height: Self.height)
  }

  override func draw(_ dirtyRect: NSRect) {
    backgroundColor.setFill()
    NSBezierPath(
      roundedRect: bounds, xRadius: Self.height / 2, yRadius: Self.height / 2
    ).fill()
    let size = attributedText.size()
    attributedText.draw(
      at: NSPoint(
        x: (bounds.width - size.width) / 2,
        y: (bounds.height - size.height) / 2))
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  private var attributedText: NSAttributedString {
    NSAttributedString(
      string: text,
      attributes: [.font: Self.font, .foregroundColor: textColor])
  }

  private static func contrastingText(on color: NSColor) -> NSColor {
    guard let rgb = color.usingColorSpace(.sRGB) else {
      return .white
    }
    let luminance =
      0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent
      + 0.0722 * rgb.blueComponent
    return luminance > 0.55 ? .black : .white
  }
}

/// An extension's popup: its page, in a popover fitted to the page's size.
@MainActor
final class ExtensionPopup: NSObject, FiberExtensionPopup, NSPopoverDelegate {
  /// Called when the user closes the popup, by clicking away from it.
  var onUserClose: () -> Void = {}

  private let popover = NSPopover()
  private let container = PopupBackground()
  private let actions: any FiberExtensionPopupActions
  private let anchor: () -> (NSView, NSRect)?
  private var isClosed = false

  init(
    contentsView: NSView, actions: any FiberExtensionPopupActions,
    anchor: @escaping () -> (NSView, NSRect)?
  ) {
    self.actions = actions
    self.anchor = anchor
    super.init()
    contentsView.frame = container.bounds
    contentsView.autoresizingMask = [.width, .height]
    container.addSubview(contentsView)
    let controller = NSViewController()
    controller.view = container
    popover.contentViewController = controller
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
  }

  func setContentSize(_ size: NSSize) {
    popover.contentSize = size
  }

  func show() {
    guard !isClosed, !popover.isShown else {
      return
    }
    guard let (view, rect) = anchor() else {
      // Nowhere to show it.
      DispatchQueue.main.async { [weak self] in self?.userDidClose() }
      return
    }
    popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
  }

  func close() {
    isClosed = true
    popover.close()
  }

  func popoverWillClose(_ notification: Notification) {
    if !isClosed {
      onUserClose()
    }
  }

  func popoverDidClose(_ notification: Notification) {
    userDidClose()
  }

  private func userDidClose() {
    guard !isClosed else {
      return
    }
    isClosed = true
    actions.extensionPopupDidClose()
  }
}

/// Behind a popup's page, which may not draw a background of its own: the
/// window's background color, as Chrome's popup bubble has its own, rather
/// than the glass (and what's behind it) showing through.
@MainActor
private final class PopupBackground: NSView {
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
  }
}
