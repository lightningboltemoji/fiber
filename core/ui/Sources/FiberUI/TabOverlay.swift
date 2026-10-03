import AppKit
import FiberBridge
import SwiftUI

/// The window's tabs, over the dimmed page with Command-S: those that aren't
/// pins', in the tab strip's order, in a panel as wide as the command
/// palette's, with the pins (PinGrid) in rows above it, and the page's address
/// and the extensions beside it. The arrow keys, Return and Command-Delete
/// move through, switch to and close them. This view takes the events and
/// keeps the model; TabOverlayView draws.
@MainActor
final class TabOverlay: NSView, NSViewToolTipOwner {
  /// Not called for the tab that's already active.
  var onSelect: (Int) -> Void = { _ in }
  /// Called with the ID of a tab to close.
  var onClose: (Int) -> Void = { _ in }
  var onOpenPin: (String) -> Void = { _ in }
  /// Called with a pin dropped in a new place, and its index there.
  var onMovePin: (String, Int) -> Void = { _, _ in }
  var onUnpin: (String) -> Void = { _ in }
  /// Right-clicks (or Control-clicks) on a pin or a tab, for their menus.
  var onPinMenu: (FiberPinState, NSEvent) -> Void = { _, _ in }
  var onTabMenu: (Int, NSEvent) -> Void = { _, _ in }
  var onAddressClick: () -> Void = {}
  /// Called when the overlay is done: the user picked something, pressed
  /// Escape, or clicked outside it. Its owner closes it.
  var onDismiss: () -> Void = {}
  var onShowOrHide: () -> Void = {}
  let extensionsBar = ExtensionsBar()
  private(set) var isOpen = false

  /// Between the panel and the address and extensions beside it.
  private static let bubbleSpacing: CGFloat = 12
  /// How close the address and extensions come to the window's edge before
  /// they move above the panel and its pins.
  private static let bubbleMargin: CGFloat = 16
  private static let maxAddressWidth: CGFloat = 260
  /// How much of the window's height the panel and what's above it leave
  /// free goes above them, a little less than below.
  private static let topShare: CGFloat = 0.45
  /// How far a pressed pin moves before it's dragged rather than clicked.
  private static let dragThreshold: CGFloat = 4

  private let model = TabOverlayModel()
  private let hostingView: NSHostingView<TabOverlayView>
  private let addressBubble = RimmedGlassView(rimWidth: GlassCapsule.rimWidth)
  private let addressButton = TabOverlay.makeAddressButton()
  private let extensionsBubble = RimmedGlassView(
    rimWidth: GlassCapsule.rimWidth)
  private let isIncognito: Bool
  /// All the window's tabs; the panel lists those that aren't pins'.
  private var tabs: [FiberTabState] = []
  /// Where the fingers have scrolled the list to, before rubber-banding.
  private var dragOffset: CGFloat = 0
  private var pressedTabID: Int?
  private var pressedCloseButtonTabID: Int?
  private var pressedPin: (pinID: String, point: CGPoint)?
  /// Set once the window has its first pins, which appear without a flourish.
  private var hasPins = false
  /// The pins the list is below, and whose tabs it leaves out. They catch up
  /// with pins leaving once those have popped out, so the list waits to
  /// change.
  private var panelPins: [FiberPinState] = []
  private var isPanelCatchUpPending = false
  /// The panel's top as it opened, kept while it fits so that closing a tab
  /// brings the next under the pointer rather than recentering the panel.
  private var heldTop: CGFloat?

  init(isIncognito: Bool) {
    self.isIncognito = isIncognito
    hostingView = NSHostingView(rootView: TabOverlayView(model: model))
    super.init(frame: .zero)
    wantsLayer = true
    isHidden = true
    alphaValue = 0
    hostingView.sizingOptions = []
    // The model's coordinates are the view's, title bar included.
    hostingView.safeAreaRegions = []
    addSubview(hostingView)
    for bubble in [addressBubble, extensionsBubble] {
      bubble.cornerRadius = GlassCapsule.height / 2
      addSubview(bubble)
    }
    addressButton.target = self
    addressButton.action = #selector(addressClicked(_:))
    addressBubble.contentView = Self.capsuleContent(
      addressButton, fillingWidth: true)
    extensionsBubble.contentView = Self.capsuleContent(
      extensionsBar, fillingWidth: false)
    // Pinning an extension widens its capsule.
    extensionsBar.onResize = { [weak self] in self?.layoutPanel() }
    setAddress("")
    model.onSelect = { [weak self] tabID in self?.pick(tabID) }
    model.onClose = { [weak self] tabID in self?.onClose(tabID) }
    model.onOpenPin = { [weak self] pinID in self?.openPin(pinID) }
    model.onUnpin = { [weak self] pinID in self?.onUnpin(pinID) }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [
          .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow,
          .inVisibleRect,
        ],
        owner: self))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // MARK: Showing

  /// Fades the overlay in, with the keyboard, and the active tab (or its pin)
  /// selected.
  func open() {
    guard !isOpen else {
      return
    }
    isOpen = true
    model.selection = initialSelection
    model.closeButton = nil
    heldTop = nil
    layoutPanel()
    revealSelection(animated: false)
    isHidden = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = PaletteView.fadeInDuration
      animator().alphaValue = 1
    }
    window?.makeFirstResponder(self)
    onShowOrHide()
  }

  func close() {
    guard isOpen else {
      return
    }
    isOpen = false
    pressedPin = nil
    model.pinDrag = nil
    if window?.firstResponder === self {
      window?.makeFirstResponder(nil)
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = PaletteView.fadeOutDuration
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        if let self, !self.isOpen {
          self.isHidden = true
        }
      }
    }
    onShowOrHide()
  }

  /// Shows the page's short address (usually just its host), or a prompt when
  /// there's none, as on the New Tab page.
  func setAddress(_ address: String) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingMiddle
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let color = address.isEmpty ? NSColor.tertiaryLabelColor : .labelColor
    let title = NSMutableAttributedString()
    if isIncognito {
      // Like Safari's Private Browsing. An attachment's symbol doesn't take
      // the text's color.
      let symbol = NSTextAttachment()
      symbol.image = NSImage(
        systemSymbolName: "mustache", accessibilityDescription: "Incognito"
      )?.withSymbolConfiguration(
        .init(pointSize: font.pointSize, weight: .medium)
          .applying(.init(paletteColors: [color])))
      title.append(NSAttributedString(attachment: symbol))
      title.append(NSAttributedString(string: " "))
    }
    title.append(
      NSAttributedString(
        string: address.isEmpty ? "Search or enter address" : address))
    title.addAttributes(
      [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
      range: NSRange(location: 0, length: title.length))
    addressButton.attributedTitle = title
    layoutPanel()
  }

  // MARK: Tabs and pins

  func setTabs(_ tabs: [FiberTabState], activeTabID: Int) {
    self.tabs = tabs
    model.activeTabID = activeTabID
    updateListedTabs()
  }

  func setPins(_ pins: [FiberPinState]) {
    let countChanged = pins.count != model.pins.count
    if hasPins, isOpen {
      burst(from: model.pins, to: pins)
    }
    hasPins = true
    let arePinsLeaving = pins.count < model.pins.count
    model.pins = pins
    if case .pin(let pinID)? = model.selection,
      !pins.contains(where: { $0.pinID == pinID })
    {
      model.selection = initialSelection
    }
    if arePinsLeaving, isOpen {
      schedulePanelCatchUp()
    } else if !isPanelCatchUpPending {
      catchUpPanel()
    }
    if countChanged {
      updatePinToolTips()
    }
  }

  /// A flourish where each pin that came or went is, or was.
  private func burst(from old: [FiberPinState], to new: [FiberPinState]) {
    let oldIDs = Set(old.map(\.pinID))
    let newIDs = Set(new.map(\.pinID))
    let changed =
      old.enumerated().filter { !newIDs.contains($0.element.pinID) }
      + new.enumerated().filter { !oldIDs.contains($0.element.pinID) }
    guard !changed.isEmpty else {
      return
    }
    let bursts = changed.map { index, pin in
      PinBurst(
        origin: PinGridLayout.origin(of: index, width: model.gridWidth),
        color: pin.favicon?.burstColor)
    }
    model.pinBursts += bursts
    let ids = Set(bursts.map(\.id))
    DispatchQueue.main.asyncAfter(deadline: .now() + PinBurstView.duration) {
      [weak self] in
      MainActor.assumeIsolated {
        self?.model.pinBursts.removeAll { ids.contains($0.id) }
      }
    }
  }

  private func schedulePanelCatchUp() {
    guard !isPanelCatchUpPending else {
      return
    }
    isPanelCatchUpPending = true
    DispatchQueue.main.asyncAfter(deadline: .now() + PinGridLayout.popOutDuration)
    { [weak self] in
      MainActor.assumeIsolated {
        self?.isPanelCatchUpPending = false
        self?.catchUpPanel()
      }
    }
  }

  private func catchUpPanel() {
    panelPins = model.pins
    model.panelPinCount = panelPins.count
    updateListedTabs()
  }

  private func updateListedTabs() {
    let pinTabIDs = Set(panelPins.map(\.tabID))
    let previous = model.tabs
    model.tabs = tabs.filter { !pinTabIDs.contains($0.tabID) }
    // A selected tab that's gone, closed say, leaves the selection to the one
    // in its place.
    if case .tab(let tabID)? = model.selection,
      !model.tabs.contains(where: { $0.tabID == tabID })
    {
      let row = previous.firstIndex { $0.tabID == tabID } ?? 0
      model.selection =
        model.tabs.isEmpty
        ? model.pins.first.map { .pin($0.pinID) }
        : .tab(model.tabs[min(row, model.tabs.count - 1)].tabID)
    }
    layoutPanel()
    // Clicking a close button moves the tabs under the pointer.
    if model.closeButton != nil, let window {
      hover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
  }

  /// The active tab's pin, or the active tab.
  private var initialSelection: TabOverlaySelection? {
    let activeTabID = model.activeTabID
    if let pin = model.pins.first(where: {
      $0.tabID != 0 && $0.tabID == activeTabID
    }) {
      return .pin(pin.pinID)
    }
    if model.tabs.contains(where: { $0.tabID == activeTabID }) {
      return .tab(activeTabID)
    }
    return (model.tabs.first?.tabID).map { .tab($0) }
      ?? (model.pins.first?.pinID).map { .pin($0) }
  }

  // MARK: Layout (flipped: y grows down from the window's top)

  override var isFlipped: Bool { true }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    hostingView.frame = bounds
    heldTop = nil
    layoutPanel()
  }

  /// The panel as wide as the command palette's, as tall as its list as far
  /// as fits, and with what's above it a little above the window's middle;
  /// the address and extensions to its left, or above the pins if narrow.
  private func layoutPanel() {
    guard bounds.width > 0 else {
      return
    }
    let (x, width, _) = PaletteView.panelPlacement(in: bounds.size)
    let height = GlassCapsule.height
    let padding = 2 * (GlassCapsule.rimWidth + GlassCapsule.endInset)
    var addressWidth = min(
      addressButton.fittingSize.width + padding, Self.maxAddressWidth)
    let extensionsWidth = extensionsBar.fittingSize.width + padding
    let columnEnd = x - Self.bubbleSpacing
    let isBeside =
      columnEnd - max(addressWidth, extensionsWidth) >= Self.bubbleMargin
    let pinsHeight = model.pinsHeight(width: width)
    let above = pinsHeight + (isBeside ? 0 : height + Self.bubbleSpacing)
    let footerHeight = TabOverlayModel.footerHeight
    let highest = PaletteView.minTop + above
    let listHeight = min(
      model.listContentHeight,
      max(bounds.height - PaletteView.bottomMargin - footerHeight - highest, 0)
    )
    let lowest = max(
      bounds.height - PaletteView.bottomMargin - footerHeight - listHeight,
      highest)
    let placed =
      ((bounds.height - above - footerHeight - listHeight) * Self.topShare)
      .rounded() + above
    let top = min(max(heldTop ?? placed, highest), lowest)
    if isOpen {
      heldTop = top
    }
    if isBeside {
      addressBubble.frame = NSRect(
        x: columnEnd - addressWidth, y: top, width: addressWidth,
        height: height)
      extensionsBubble.frame = NSRect(
        x: columnEnd - extensionsWidth,
        y: top + height + GlassCapsule.spacing, width: extensionsWidth,
        height: height)
    } else {
      addressWidth = max(
        min(addressWidth, width - extensionsWidth - GlassCapsule.spacing), 0)
      addressBubble.frame = NSRect(
        x: x, y: top - above, width: addressWidth, height: height)
      extensionsBubble.frame = NSRect(
        x: x + addressWidth + GlassCapsule.spacing, y: top - above,
        width: extensionsWidth, height: height)
    }

    let frame = CGRect(
      x: x, y: top, width: width, height: footerHeight + listHeight)
    if frame != model.panelFrame {
      model.panelFrame = frame
      updatePinToolTips()
    }
    setScrollOffset(clamp(model.scrollOffset, to: model.scrollRange))
  }

  /// `view` in the middle of a capsule's glass, as wide as its ends allow if
  /// `fillingWidth`.
  private static func capsuleContent(_ view: NSView, fillingWidth: Bool)
    -> NSView
  {
    let content = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(view)
    var constraints = [
      view.centerYAnchor.constraint(equalTo: content.centerYAnchor)
    ]
    if fillingWidth {
      constraints += [
        view.leadingAnchor.constraint(
          equalTo: content.leadingAnchor, constant: GlassCapsule.endInset),
        view.trailingAnchor.constraint(
          equalTo: content.trailingAnchor, constant: -GlassCapsule.endInset),
      ]
    } else {
      constraints.append(
        view.centerXAnchor.constraint(equalTo: content.centerXAnchor))
    }
    NSLayoutConstraint.activate(constraints)
    return content
  }

  private static func makeAddressButton() -> NSButton {
    let button = NSButton(title: "", target: nil, action: nil)
    button.bezelStyle = .accessoryBarAction
    button.borderShape = .capsule
    button.showsBorderOnlyWhileMouseInside = true
    button.toolTip = "Search or enter address"
    button.setContentCompressionResistancePriority(
      .defaultLow, for: .horizontal)
    button.heightAnchor.constraint(equalToConstant: GlassCapsule.buttonSize)
      .isActive = true
    return button
  }

  @objc private func addressClicked(_ sender: Any?) {
    onAddressClick()
  }

  // MARK: Geometry

  private func location(of event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
  }

  /// `point` from the panel's top-left corner.
  private func inPanel(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: point.x - model.panelFrame.minX, y: point.y - model.panelFrame.minY)
  }

  /// `point` in the pins' grid (see PinGridLayout).
  private func inPins(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x - model.pinsOrigin.x, y: point.y - model.pinsOrigin.y)
  }

  /// The pin at `point`, as it's shown.
  private func pin(at point: CGPoint) -> FiberPinState? {
    PinGridLayout.index(
      at: inPins(point), count: model.pins.count, width: model.gridWidth
    ).map { model.pins[$0] }
  }

  /// Whether `point` is on the panel, or on or between the pins.
  private func isOnPanelOrPins(_ point: CGPoint) -> Bool {
    model.panelFrame.contains(point)
      || PinGridLayout.covers(
        inPins(point), count: model.pins.count, width: model.gridWidth)
  }

  /// The tab at `point`, where the list is scrolled to now.
  private func tab(at point: CGPoint) -> FiberTabState? {
    let point = inPanel(point)
    let list = model.listRect
    guard list.contains(point) else {
      return nil
    }
    let offset =
      point.y - list.minY + model.scrollOffset - TabListLayout.contentInset
    guard offset >= 0 else {
      return nil
    }
    let row = Int(offset / TabListLayout.rowStep)
    return model.tabs.indices.contains(row) ? model.tabs[row] : nil
  }

  /// The close button `point` is within reach of, where the list is scrolled
  /// to now.
  private func closeButton(near point: CGPoint) -> TabCloseButton? {
    let point = inPanel(point)
    let list = model.listRect
    guard list.contains(point) else {
      return nil
    }
    return TabListLayout.closeButton(
      near: CGPoint(x: point.x, y: point.y - list.minY + model.scrollOffset),
      in: model.tabs, width: list.width)
  }

  /// The tab whose close button is at `point`, if it's showing.
  private func closeButtonTab(at point: CGPoint) -> Int? {
    guard let button = closeButton(near: point), button.isHovered,
      button.tabID == model.closeButton?.tabID
    else {
      return nil
    }
    return button.tabID
  }

  /// Scrolls the least that shows the selected tab whole.
  private func revealSelection(animated: Bool) {
    guard let tabID = model.selectedTabID,
      let row = model.tabs.firstIndex(where: { $0.tabID == tabID })
    else {
      return
    }
    let top = CGFloat(row) * TabListLayout.rowStep
    let bottom =
      top + TabListLayout.rowHeight + 2 * TabListLayout.contentInset
      - model.listRect.height
    let offset = min(
      max(clamp(model.scrollOffset, to: model.scrollRange), bottom), top)
    setScrollOffset(
      offset, animation: animated ? .spring(duration: 0.25, bounce: 0) : nil)
  }

  private func setScrollOffset(_ offset: CGFloat, animation: Animation? = nil)
  {
    guard offset != model.scrollOffset else {
      return
    }
    withAnimation(animation) {
      model.scrollOffset = offset
    }
  }

  // MARK: Tooltips

  /// A pin shows only its icon, so its title shows on hover.
  private func updatePinToolTips() {
    removeAllToolTips()
    let pins = model.pinsOrigin
    for index in model.pins.indices {
      let origin = PinGridLayout.origin(of: index, width: model.gridWidth)
      addToolTip(
        NSRect(
          x: pins.x + origin.x, y: pins.y + origin.y,
          width: PinGridLayout.diameter, height: PinGridLayout.diameter),
        owner: self, userData: nil)
    }
  }

  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData data: UnsafeMutableRawPointer?
  ) -> String {
    guard let pin = pin(at: point) else {
      return ""
    }
    return pin.title.isEmpty ? pin.url : pin.title
  }

  // MARK: Keyboard

  override var acceptsFirstResponder: Bool { true }

  /// While open, it keeps the keyboard, which Chrome gives a page it switches
  /// to (as when the active tab closes).
  override func resignFirstResponder() -> Bool {
    !isOpen
  }

  override func keyDown(with event: NSEvent) {
    // The key bindings take Command-Delete as deleting to the line's start.
    if event.charactersIgnoringModifiers == "\u{7F}",
      event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        == .command
    {
      closeSelection()
      return
    }
    interpretKeyEvents([event])
  }

  override func moveUp(_ sender: Any?) {
    moveSelection(.up)
  }

  override func moveDown(_ sender: Any?) {
    moveSelection(.down)
  }

  override func moveLeft(_ sender: Any?) {
    moveSelection(.left)
  }

  override func moveRight(_ sender: Any?) {
    moveSelection(.right)
  }

  override func insertTab(_ sender: Any?) {
    stepSelection(by: 1)
  }

  override func insertBacktab(_ sender: Any?) {
    stepSelection(by: -1)
  }

  override func insertNewline(_ sender: Any?) {
    switch model.selection {
    case .pin(let pinID)?:
      openPin(pinID)
    case .tab(let tabID)?:
      pick(tabID)
    case nil:
      onDismiss()
    }
  }

  override func cancelOperation(_ sender: Any?) {
    onDismiss()
  }

  private enum Direction {
    case up, down, left, right
  }

  private func moveSelection(_ direction: Direction) {
    guard let next = selection(after: model.selection, moving: direction)
    else {
      return
    }
    select(next)
  }

  /// Through the pins as a grid whose rows rise from the tabs, then the tabs
  /// as a column.
  private func selection(
    after selection: TabOverlaySelection?, moving direction: Direction
  ) -> TabOverlaySelection? {
    let pins = model.pins
    let tabs = model.tabs
    let columns = PinGridLayout.columns(width: model.gridWidth)
    let topRowStart = (max(pins.count, 1) - 1) / columns * columns
    switch selection {
    case .pin(let pinID)?:
      guard let index = pins.firstIndex(where: { $0.pinID == pinID }) else {
        return initialSelection
      }
      switch direction {
      case .left, .right:
        let next = index + (direction == .left ? -1 : 1)
        return pins.indices.contains(next) ? .pin(pins[next].pinID) : nil
      case .up:
        return index >= topRowStart
          ? nil : .pin(pins[min(index + columns, pins.count - 1)].pinID)
      case .down:
        return index < columns
          ? tabs.first.map { .tab($0.tabID) } : .pin(pins[index - columns].pinID)
      }
    case .tab(let tabID)?:
      guard let index = tabs.firstIndex(where: { $0.tabID == tabID }) else {
        return initialSelection
      }
      switch direction {
      case .up where index == 0:
        return pins.first.map { .pin($0.pinID) }
      case .up:
        return .tab(tabs[index - 1].tabID)
      case .down:
        return index + 1 < tabs.count ? .tab(tabs[index + 1].tabID) : nil
      case .left, .right:
        return nil
      }
    case nil:
      return initialSelection
    }
  }

  /// Tab and Shift-Tab go through the pins and tabs in reading order.
  private func stepSelection(by step: Int) {
    let items =
      model.pins.map { TabOverlaySelection.pin($0.pinID) }
      + model.tabs.map { .tab($0.tabID) }
    guard let current = model.selection.flatMap(items.firstIndex(of:)) else {
      select(initialSelection)
      return
    }
    let next = current + step
    if items.indices.contains(next) {
      select(items[next])
    }
  }

  private func select(_ selection: TabOverlaySelection?) {
    guard selection != model.selection else {
      return
    }
    model.selection = selection
    revealSelection(animated: true)
  }

  /// A pin's tab, if it's open, or the tab.
  private func closeSelection() {
    switch model.selection {
    case .pin(let pinID)?:
      if let pin = model.pins.first(where: { $0.pinID == pinID }),
        pin.tabID != 0
      {
        onClose(pin.tabID)
      }
    case .tab(let tabID)?:
      onClose(tabID)
    case nil:
      break
    }
  }

  // Dismissing after, so the page given the keyboard is the one switched to.

  private func pick(_ tabID: Int) {
    if tabID != model.activeTabID {
      onSelect(tabID)
    }
    onDismiss()
  }

  private func openPin(_ pinID: String) {
    onOpenPin(pinID)
    onDismiss()
  }

  // MARK: Pointer

  /// Everything but the address and extensions, which take their own clicks.
  /// The page under it takes none.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard isOpen, let view = super.hitTest(point) else {
      return nil
    }
    let isInBubble = [addressBubble, extensionsBubble].contains {
      view.isDescendant(of: $0)
    }
    return isInBubble ? view : self
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    guard let window else {
      return
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(windowDidResignKey(_:)),
      name: NSWindow.didResignKeyNotification, object: window)
  }

  @objc private func windowDidResignKey(_ notification: Notification) {
    hover(at: nil)
  }

  override func mouseMoved(with event: NSEvent) {
    hover(at: location(of: event))
  }

  override func mouseEntered(with event: NSEvent) {
    hover(at: location(of: event))
  }

  override func mouseExited(with event: NSEvent) {
    hover(at: nil)
  }

  override func mouseDown(with event: NSEvent) {
    let point = location(of: event)
    guard isOnPanelOrPins(point) else {
      onDismiss()
      return
    }
    if event.modifierFlags.contains(.control) {
      showMenu(for: event)
      return
    }
    if let pin = pin(at: point) {
      pressedPin = (pin.pinID, point)
      return
    }
    pressedCloseButtonTabID = closeButtonTab(at: point)
    if pressedCloseButtonTabID == nil {
      pressedTabID = tab(at: point)?.tabID
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let pressedPin,
      let from = model.pins.firstIndex(where: { $0.pinID == pressedPin.pinID })
    else {
      return
    }
    let point = location(of: event)
    let offset = CGSize(
      width: point.x - pressedPin.point.x,
      height: point.y - pressedPin.point.y)
    guard
      model.pinDrag != nil
        || hypot(offset.width, offset.height) >= Self.dragThreshold
    else {
      return
    }
    let origin = PinGridLayout.origin(of: from, width: model.gridWidth)
    let center = CGPoint(
      x: origin.x + PinGridLayout.diameter / 2 + offset.width,
      y: origin.y + PinGridLayout.diameter / 2 + offset.height)
    model.pinDrag = PinDrag(
      pinID: pressedPin.pinID, offset: offset,
      targetIndex: PinGridLayout.nearestIndex(
        to: center, count: model.pins.count, width: model.gridWidth))
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      pressedTabID = nil
      pressedCloseButtonTabID = nil
      pressedPin = nil
    }
    let point = location(of: event)
    if let drag = model.pinDrag {
      // The browser reorders the pins before this returns, so the pin settles
      // into its new place from where it was dropped.
      if drag.targetIndex
        != model.pins.firstIndex(where: { $0.pinID == drag.pinID })
      {
        onMovePin(drag.pinID, drag.targetIndex)
      }
      model.pinDrag = nil
      hover(at: point)
      return
    }
    if let pressedPin {
      if pin(at: point)?.pinID == pressedPin.pinID {
        openPin(pressedPin.pinID)
      }
      return
    }
    if let tabID = pressedCloseButtonTabID {
      if closeButtonTab(at: point) == tabID {
        onClose(tabID)
      }
      return
    }
    guard let tabID = tab(at: point)?.tabID, tabID == pressedTabID else {
      return
    }
    pick(tabID)
  }

  override func rightMouseDown(with event: NSEvent) {
    showMenu(for: event)
  }

  private func showMenu(for event: NSEvent) {
    let point = location(of: event)
    if let pin = pin(at: point) {
      onPinMenu(pin, event)
    } else if let tab = tab(at: point) {
      onTabMenu(tab.tabID, event)
    }
  }

  /// The selection follows the pointer onto a pin or a tab. Nil for the
  /// pointer gone.
  private func hover(at point: CGPoint?) {
    if let point, isOpen, model.pinDrag == nil {
      if let pin = pin(at: point) {
        model.selection = .pin(pin.pinID)
      } else if let tab = tab(at: point) {
        model.selection = .tab(tab.tabID)
      }
    }
    let button = point.flatMap(closeButton(near:))
    if button != model.closeButton {
      model.closeButton = button
    }
  }

  // MARK: Scrolling

  /// Scrolls the list, when it's longer than the panel. Fingers can stretch
  /// it a little past either end, and it springs back when they lift; a
  /// flick coasts, and stops at the end. The page under it doesn't scroll.
  override func scrollWheel(with event: NSEvent) {
    let range = model.scrollRange
    guard range.upperBound > 0 else {
      return
    }
    let delta = -event.scrollingDeltaY
    if !event.hasPreciseScrollingDeltas {
      // A notched wheel scrolls a tab a line.
      setScrollOffset(
        clamp(model.scrollOffset + delta * TabListLayout.rowStep, to: range),
        animation: .spring(duration: 0.25, bounce: 0))
    } else if !event.momentumPhase.isEmpty {
      setScrollOffset(clamp(model.scrollOffset + delta, to: range))
    } else {
      switch event.phase {
      case .began, .changed:
        if event.phase == .began {
          dragOffset = model.scrollOffset
        }
        dragOffset += delta
        model.scrollOffset = TabListLayout.rubberBand(dragOffset, in: range)
      case .ended, .cancelled:
        setScrollOffset(
          clamp(model.scrollOffset, to: range),
          animation: .spring(duration: 0.35, bounce: 0))
      case []:
        // A precise device without phases.
        setScrollOffset(clamp(model.scrollOffset + delta, to: range))
      default:
        break
      }
    }
    hover(at: location(of: event))
  }

  private func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>)
    -> CGFloat
  {
    min(max(value, range.lowerBound), range.upperBound)
  }
}

/// What Return and Command-Delete act on in the tab overlay.
enum TabOverlaySelection: Equatable {
  case pin(String)
  case tab(Int)
}

@MainActor
@Observable
final class TabOverlayModel {
  /// The hints under the list, and the rim below them.
  static let footerHeight = PaletteView.footerHeight + PaletteView.rimWidth

  /// The tabs the list shows: those that aren't pins'.
  var tabs: [FiberTabState] = []
  var pins: [FiberPinState] = []
  var activeTabID = 0
  var selection: TabOverlaySelection?
  var pinDrag: PinDrag?
  var pinBursts: [PinBurst] = []
  /// How many pins the list is below (see TabOverlay.panelPins).
  var panelPinCount = 0
  var closeButton: TabCloseButton?
  /// How far the list is scrolled up the panel.
  var scrollOffset: CGFloat = 0
  /// In the overlay, as tall as fits.
  var panelFrame: CGRect = .zero
  @ObservationIgnored var onSelect: (Int) -> Void = { _ in }
  @ObservationIgnored var onClose: (Int) -> Void = { _ in }
  @ObservationIgnored var onOpenPin: (String) -> Void = { _ in }
  @ObservationIgnored var onUnpin: (String) -> Void = { _ in }

  var gridWidth: CGFloat { panelFrame.width }

  /// The bottom-left corner of the pins' grid, just above the panel.
  var pinsOrigin: CGPoint {
    CGPoint(x: panelFrame.minX, y: panelFrame.minY - PinGridLayout.spacing)
  }

  var selectedTabID: Int? {
    if case .tab(let tabID)? = selection {
      return tabID
    }
    return nil
  }

  /// The pins in the order they show: a dragged one where it would drop.
  var shownPins: [FiberPinState] {
    guard let pinDrag,
      let from = pins.firstIndex(where: { $0.pinID == pinDrag.pinID })
    else {
      return pins
    }
    var shown = pins
    let pin = shown.remove(at: from)
    shown.insert(pin, at: min(pinDrag.targetIndex, shown.count))
    return shown
  }

  /// The pins' rows over a panel `width` wide, and the space under them.
  func pinsHeight(width: CGFloat) -> CGFloat {
    guard panelPinCount > 0 else {
      return 0
    }
    return PinGridLayout.height(count: panelPinCount, width: width)
      + PinGridLayout.spacing
  }

  var listContentHeight: CGFloat {
    tabs.isEmpty ? 0 : TabListLayout.panelHeight(rows: tabs.count)
  }

  /// From the panel's top-left corner.
  var listRect: CGRect {
    CGRect(
      x: 0, y: 0, width: panelFrame.width,
      height: max(panelFrame.height - Self.footerHeight, 0))
  }

  var scrollRange: ClosedRange<CGFloat> {
    0...max(listContentHeight - listRect.height, 0)
  }
}

/// Draws the tab overlay's panel and pins; TabOverlay handles all input. The
/// highlight glides to the selected tab.
struct TabOverlayView: View {
  let model: TabOverlayModel

  var body: some View {
    let panel = model.panelFrame
    let list = model.listRect
    let rim = PaletteView.rimWidth
    let pins = model.pinsOrigin
    ZStack(alignment: .topLeading) {
      ZStack(alignment: .topLeading) {
        PanelShadow(cornerRadius: PaletteView.cornerRadius)
        RimmedGlass(cornerRadius: PaletteView.cornerRadius, rimWidth: rim)
          .accessibilityHidden(true)

        TabList(
          width: panel.width, showsURL: true, tabs: model.tabs,
          activeTabID: model.activeTabID,
          highlightedTabID: model.selectedTabID,
          closeButton: model.closeButton, onSelect: model.onSelect,
          onClose: model.onClose
        )
        .fixedSize(horizontal: false, vertical: true)
        .offset(y: -model.scrollOffset)
        .frame(width: panel.width, height: list.height, alignment: .top)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")

        HintsView()
          .frame(
            width: max(
              panel.width - 2 * (rim + PaletteView.horizontalInset), 0),
            height: PaletteView.footerHeight, alignment: .trailing
          )
          .offset(
            x: rim + PaletteView.horizontalInset,
            y: panel.height - TabOverlayModel.footerHeight)
      }
      .frame(width: panel.width, height: panel.height, alignment: .topLeading)
      .offset(x: panel.minX, y: panel.minY)

      PinGrid(model: model)
        .frame(
          width: panel.width, height: max(pins.y, 0), alignment: .bottomLeading
        )
        .offset(x: pins.x)
        // Read before the tabs, as they show.
        .accessibilitySortPriority(1)
    }
    // Tabs opening and closing grow and shrink the panel, and rows of pins
    // coming and going can move it.
    .animation(
      .spring(duration: 0.3, bounce: 0), value: model.tabs.map(\.tabID))
    .animation(.spring(duration: 0.3, bounce: 0), value: model.panelPinCount)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain)
  }
}

/// The keys, like the command palette's.
private struct HintsView: View {
  private static let hints = [
    ("Switch to Tab", "↩"), ("Close Tab", "⌘⌫"), ("Close", "esc"),
  ]

  var body: some View {
    HStack(spacing: PaletteView.hintSpacing) {
      ForEach(Self.hints, id: \.0) { action, key in
        HStack(spacing: PaletteView.hintInnerSpacing) {
          Text(action)
            .foregroundStyle(.secondary)
          Text(key)
            .fontWeight(.medium)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .font(.system(size: 11))
  }
}
