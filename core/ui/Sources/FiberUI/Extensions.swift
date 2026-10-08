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

/// A window's extensions: the menu (ExtensionsMenu) from the tab overlay's
/// puzzle piece, the pinned extensions' buttons (ExtensionsBar), their popups
/// (ExtensionPopup), which open from the puzzle piece when unpinned, and the
/// bubbles for the windows they open (ExtensionBubbles).
@MainActor
final class ExtensionsController: NSObject, FiberExtensions {
  var actions: (any FiberExtensionsActions)?

  private let bar: ExtensionsBar
  private let bubbles: ExtensionBubbles
  private let popupLayer: ExtensionPopupLayer
  private let restoreFocus: () -> Void
  private let isBarShown: () -> Bool
  /// Where the bar's menu button is, in the window's content view, for
  /// popups while the tab overlay is closed.
  private let hiddenMenuButtonRect: () -> (NSView, NSRect)?
  private var extensions: [FiberExtensionState] = []
  private var menu: ExtensionsMenu?
  private weak var popup: ExtensionPopup?
  /// The click that last closed the menu or a popup (see CapsuleButton), so
  /// the same click on its button doesn't open it again.
  private var closingClick: (button: String, timestamp: TimeInterval)?

  init(
    bar: ExtensionsBar, bubbles: ExtensionBubbles,
    popupLayer: ExtensionPopupLayer, restoreFocus: @escaping () -> Void,
    isBarShown: @escaping () -> Bool,
    hiddenMenuButtonRect: @escaping () -> (NSView, NSRect)?
  ) {
    self.bar = bar
    self.bubbles = bubbles
    self.popupLayer = popupLayer
    self.restoreFocus = restoreFocus
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
      contentsView: contentsView, actions: actions, layer: popupLayer,
      anchor: { [weak self] in self?.popupAnchor(for: extensionID) },
      restoreFocus: restoreFocus)
    popup.onUserClose = { [weak self] in
      self?.noteClosingClick(for: extensionID)
    }
    self.popup = popup
    return popup
  }

  func extensionWindow(with actions: any FiberExtensionWindowActions)
    -> any FiberExtensionWindow
  {
    bubbles.add(actions: actions)
  }

  func windowWillClose() {
    closeMenu()
  }

  /// For what opens that the popup would cover (see
  /// ExtensionPopup.closeForReplacement()).
  func closePopup() {
    popup?.closeForReplacement()
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

  @objc private func menuButtonClicked(_ sender: CapsuleButton) {
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

  /// The menu and popups close on a click outside them before the click
  /// reaches whatever was clicked; if that's the button that opened one, the
  /// click only closes it.
  private func noteClosingClick(for key: String) {
    guard let event = NSApp.currentEvent,
      event.type == .leftMouseDown || event.type == .rightMouseDown
    else {
      return
    }
    closingClick = (key, event.timestamp)
  }

  private func closedByThisClick(_ button: CapsuleButton, key: String) -> Bool
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

/// A capsule's button that notes when it's pressed, so a click that closed its
/// menu or popup doesn't open it again (see ExtensionsController).
class CapsuleButton: NSButton {
  private(set) var mouseDownTimestamp: TimeInterval = -1

  override func mouseDown(with event: NSEvent) {
    mouseDownTimestamp = event.timestamp
    super.mouseDown(with: event)
  }
}

/// The extensions' capsule in the tab overlay: the buttons of the pinned extensions,
/// then the puzzle piece that opens the extensions menu.
@MainActor
final class ExtensionsBar: NSStackView {
  let menuButton = GlassCapsule.makeButton(
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
final class ExtensionButton: CapsuleButton {
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
    widthAnchor.constraint(equalToConstant: GlassCapsule.buttonSize).isActive = true
    heightAnchor.constraint(equalToConstant: GlassCapsule.buttonSize).isActive = true
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

/// An extension's popup: its page in glass (see ExtensionPanel) by the button
/// it opened from, fitted to the page's size. It's in the window because a
/// popover's window never becomes key, which a page needs to have focus.
@MainActor
final class ExtensionPopup: NSObject, FiberExtensionPopup {
  /// Called when the user closes the popup: by clicking elsewhere in its
  /// window, or opening what it would cover.
  var onUserClose: () -> Void = {}

  private let panel = ExtensionPanel()
  private let actions: any FiberExtensionPopupActions
  private weak var layer: ExtensionPopupLayer?
  private let anchor: () -> (NSView, NSRect)?
  /// Gives the keyboard to the window's tab, when what had it before the
  /// popup can't take it back and nothing replaced the popup.
  private let restoreFocus: () -> Void
  private var contentSize = NSSize.zero
  private weak var previousResponder: NSResponder?
  private var clickMonitor: Any?
  private var isClosed = false
  private var isReplaced = false

  init(
    contentsView: NSView, actions: any FiberExtensionPopupActions,
    layer: ExtensionPopupLayer, anchor: @escaping () -> (NSView, NSRect)?,
    restoreFocus: @escaping () -> Void
  ) {
    self.actions = actions
    self.layer = layer
    self.anchor = anchor
    self.restoreFocus = restoreFocus
    super.init()
    panel.setPage(contentsView)
  }

  func setContentSize(_ size: NSSize) {
    contentSize = size
    layout()
  }

  func show() {
    guard !isClosed, panel.superview == nil, let layer else {
      return
    }
    guard anchor() != nil else {
      // Nowhere to show it.
      DispatchQueue.main.async { [weak self] in self?.userDidClose() }
      return
    }
    previousResponder = layer.window?.firstResponder
    layer.popup = self
    layer.addSubview(panel)
    layout()
    panel.alphaValue = 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      panel.animator().alphaValue = 1
    }
    clickMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      MainActor.assumeIsolated {
        self?.closeIfOutside(event)
      }
      return event
    }
  }

  func close() {
    guard !isClosed else {
      return
    }
    isClosed = true
    dismiss()
  }

  /// For what opens that it would cover (the omnibar, say), which takes the
  /// keyboard.
  func closeForReplacement() {
    isReplaced = true
    userDidClose()
  }

  /// Above the button it opened from, or below it if there's no room or
  /// above would cover what the layer keeps clear and below wouldn't,
  /// centered on it and within the window.
  fileprivate func layout() {
    guard let layer = panel.superview as? ExtensionPopupLayer,
      let (view, rect) = anchor()
    else {
      return
    }
    let button = layer.convert(rect, from: view)
    let bounds = layer.bounds.insetBy(
      dx: ExtensionBubbles.margin, dy: ExtensionBubbles.margin)
    let size = panel.frameSize(forPage: contentSize)
    let width = min(size.width, bounds.width)
    let height = min(size.height, bounds.height)
    let x = ExtensionBubbleLayout.clamp(
      button.midX - width / 2, bounds.minX, bounds.maxX - width)
    let obstacles = layer.keepClear().map {
      $0.insetBy(dx: -GlassCapsule.spacing, dy: -GlassCapsule.spacing)
    }
    func fitsClear(_ y: CGFloat) -> Bool {
      let frame = NSRect(x: x, y: y, width: width, height: height)
      return frame.minY >= bounds.minY && frame.maxY <= bounds.maxY
        && !obstacles.contains { $0.intersects(frame) }
    }
    let above = button.minY - GlassCapsule.spacing - height
    let below = button.maxY + GlassCapsule.spacing
    let y =
      fitsClear(above) || (above >= bounds.minY && !fitsClear(below))
      ? above : min(below, bounds.maxY - height)
    panel.frame = NSRect(x: x, y: y, width: width, height: height)
  }

  /// As in Chrome, it stays open while another window has the focus (a save
  /// panel the page opened, which needs the page alive to save), and closes
  /// on a click elsewhere in its window.
  private func closeIfOutside(_ event: NSEvent) {
    guard let window = panel.window, event.window === window,
      !panel.bounds.contains(panel.convert(event.locationInWindow, from: nil))
    else {
      return
    }
    userDidClose()
  }

  private func userDidClose() {
    guard !isClosed else {
      return
    }
    isClosed = true
    onUserClose()
    dismiss()
    actions.extensionPopupDidClose()
  }

  private func dismiss() {
    if let clickMonitor {
      NSEvent.removeMonitor(clickMonitor)
      self.clickMonitor = nil
    }
    guard panel.superview != nil else {
      return
    }
    if hasKeyboard {
      giveKeyboardBack()
    }
    let panel = panel
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      panel.animator().alphaValue = 0
    } completionHandler: {
      MainActor.assumeIsolated {
        panel.removeFromSuperview()
      }
    }
  }

  private var hasKeyboard: Bool {
    guard let responder = panel.window?.firstResponder as? NSView else {
      return false
    }
    return responder.isDescendant(of: panel)
  }

  /// To what had it as the popup showed (the tab overlay, say), if that's
  /// still in the window and can take it.
  private func giveKeyboardBack() {
    if let window = panel.window, let previous = previousResponder,
      previous === window || (previous as? NSView)?.window === window,
      window.makeFirstResponder(previous)
    {
      return
    }
    if !isReplaced {
      restoreFocus()
    }
  }
}

/// Over the tab overlay, whose extensions' buttons popups open from, and the
/// traffic lights: the window's extension popup. Clicks anywhere else go
/// through.
@MainActor
final class ExtensionPopupLayer: NSView {
  /// What a popup opens below its button rather than cover, if it can (in
  /// this view).
  var keepClear: () -> [NSRect] = { [] }

  fileprivate weak var popup: ExtensionPopup?

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let view = super.hitTest(point)
    return view === self ? nil : view
  }

  // The window's other views have laid out by now, the popup's button with
  // them.
  override func resizeSubviews(withOldSize oldSize: NSSize) {
    popup?.layout()
  }
}
