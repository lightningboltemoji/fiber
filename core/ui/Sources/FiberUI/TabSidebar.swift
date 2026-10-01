import AppKit
import FiberBridge
import SwiftUI

/// The window's tabs while the toolbar shows: the pins (PinGrid), then the
/// other tabs in the tab strip's order, in a panel like the tab picker's
/// kept open below the toolbar. It fills the column they can grow into, but
/// only they take clicks. TabSidebarView draws it.
@MainActor
final class TabSidebar: NSView, NSViewToolTipOwner {
  static let width = TabListLayout.panelWidth

  /// Not called for the tab that's already active.
  var onSelect: (Int) -> Void = { _ in }
  /// Called with the ID of a tab whose close button was clicked.
  var onClose: (Int) -> Void = { _ in }
  /// Called with the ID of a pin that was clicked, unless it was its active
  /// tab's close button.
  var onOpenPin: (String) -> Void = { _ in }
  /// Called with a pin dropped in a new place, and its index there.
  var onMovePin: (String, Int) -> Void = { _, _ in }
  var onUnpin: (String) -> Void = { _ in }
  /// Right-clicks (or Control-clicks) on a pin or a tab, for their menus.
  var onPinMenu: (FiberPinState, NSEvent) -> Void = { _, _ in }
  var onTabMenu: (Int, NSEvent) -> Void = { _, _ in }

  /// How far a pressed pin moves before it's dragged rather than clicked.
  private static let dragThreshold: CGFloat = 4

  private let model = TabSidebarModel()
  private let hostingView: NSHostingView<TabSidebarView>
  /// All the window's tabs; the panel lists those that aren't pins'.
  private var tabs: [FiberTabState] = []
  /// Where the fingers have scrolled the list to, before rubber-banding.
  private var dragOffset: CGFloat = 0
  private var pressedTabID: Int?
  private var pressedCloseButtonTabID: Int?
  private var pressedPin: (pinID: String, point: CGPoint)?
  /// Set once the window has its first pins, which appear without a flourish.
  private var hasPins = false
  /// The pins the panel is below, and whose tabs it leaves out. They catch up
  /// with pins leaving once those have popped out, so the panel waits to move.
  private var panelPins: [FiberPinState] = []
  private var isPanelCatchUpPending = false

  override init(frame: NSRect) {
    hostingView = NSHostingView(rootView: TabSidebarView(model: model))
    super.init(frame: frame)
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    model.size = bounds.size
    model.onSelect = { [weak self] tabID in self?.pick(tabID) }
    model.onClose = { [weak self] tabID in self?.onClose(tabID) }
    model.onOpenPin = { [weak self] pinID in self?.onOpenPin(pinID) }
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

  func setTabs(_ tabs: [FiberTabState], activeTabID: Int) {
    self.tabs = tabs
    let activeChanged = activeTabID != model.activeTabID
    model.activeTabID = activeTabID
    updateListedTabs(revealingActiveTab: activeChanged)
  }

  func setPins(_ pins: [FiberPinState]) {
    let heightChanged = pins.count != model.pins.count
    if hasPins, !isHidden {
      burst(from: model.pins, to: pins)
    }
    hasPins = true
    let arePinsLeaving = pins.count < model.pins.count
    model.pins = pins
    if arePinsLeaving, !isHidden {
      schedulePanelCatchUp()
    } else if !isPanelCatchUpPending {
      catchUpPanel()
    }
    if heightChanged {
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
        origin: PinGridLayout.origin(of: index, width: model.size.width),
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
    updateListedTabs(revealingActiveTab: false)
  }

  private func updateListedTabs(revealingActiveTab: Bool) {
    let pinTabIDs = Set(panelPins.map(\.tabID))
    model.tabs = tabs.filter { !pinTabIDs.contains($0.tabID) }
    // Only a new active tab moves the list: a page's title or icon changing
    // leaves it where the user scrolled it.
    if revealingActiveTab {
      revealActiveTab(animated: !isHidden)
    } else {
      setScrollOffset(clamp(model.scrollOffset, to: model.scrollRange))
    }
    // The tabs may have moved under the pointer, as they do when it closes
    // one.
    if model.hoveredTabID != nil || model.closeButton != nil
      || model.hoveredPinID != nil, let window
    {
      hover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
  }

  // MARK: Geometry (flipped: y grows down from the column's top)

  override var isFlipped: Bool { true }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    model.size = newSize
    revealActiveTab(animated: false)
    updatePinToolTips()
  }

  private func location(of event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
  }

  /// The pin at `point`, as it's shown.
  private func pin(at point: CGPoint) -> FiberPinState? {
    PinGridLayout.index(
      at: point, count: model.pins.count, width: model.size.width
    ).map { model.pins[$0] }
  }

  /// The tab at `point`, where the list is scrolled to now.
  private func tab(at point: CGPoint) -> FiberTabState? {
    guard model.panelRect.contains(point) else {
      return nil
    }
    let offset =
      point.y - model.panelRect.minY + model.scrollOffset
      - TabListLayout.contentInset
    guard offset >= 0 else {
      return nil
    }
    let row = Int(offset / TabListLayout.rowStep)
    return model.tabs.indices.contains(row) ? model.tabs[row] : nil
  }

  /// The close button `point` is within reach of, where the list is scrolled
  /// to now.
  private func closeButton(near point: CGPoint) -> TabCloseButton? {
    guard model.panelRect.contains(point) else {
      return nil
    }
    return TabListLayout.closeButton(
      near: CGPoint(
        x: point.x, y: point.y - model.panelRect.minY + model.scrollOffset),
      in: model.tabs)
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

  /// Scrolls the least that shows the active tab whole, clear of the rim.
  private func revealActiveTab(animated: Bool) {
    var offset = clamp(model.scrollOffset, to: model.scrollRange)
    if let row = model.tabs.firstIndex(where: { $0.tabID == model.activeTabID })
    {
      let top = CGFloat(row) * TabListLayout.rowStep
      let bottom =
        top + TabListLayout.rowHeight + 2 * TabListLayout.contentInset
        - model.panelRect.height
      offset = min(max(offset, bottom), top)
    }
    setScrollOffset(
      offset, animation: animated ? .spring(duration: 0.35, bounce: 0) : nil)
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
    for index in model.pins.indices {
      let origin = PinGridLayout.origin(of: index, width: model.size.width)
      addToolTip(
        NSRect(
          origin: origin,
          size: CGSize(
            width: PinGridLayout.diameter, height: PinGridLayout.diameter)),
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

  // MARK: Pointer

  override func hitTest(_ point: NSPoint) -> NSView? {
    if isHidden {
      return nil
    }
    let point = convert(point, from: superview)
    let isOnPanel = model.isPanelShown && model.panelRect.contains(point)
    return isOnPanel || pin(at: point) != nil ? self : nil
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
    if event.modifierFlags.contains(.control) {
      showMenu(for: event)
      return
    }
    let point = location(of: event)
    if let pin = pin(at: point) {
      pressedPin = (pin.pinID, point)
      return
    }
    pressedCloseButtonTabID = closeButtonTab(at: point)
    guard pressedCloseButtonTabID == nil else {
      return
    }
    pressedTabID = tab(at: point)?.tabID
    if pressedTabID == nil {
      window?.performDrag(with: event)
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
    let origin = PinGridLayout.origin(of: from, width: model.size.width)
    let center = CGPoint(
      x: origin.x + PinGridLayout.diameter / 2 + offset.width,
      y: origin.y + PinGridLayout.diameter / 2 + offset.height)
    model.pinDrag = PinDrag(
      pinID: pressedPin.pinID, offset: offset,
      targetIndex: PinGridLayout.nearestIndex(
        to: center, count: model.pins.count, width: model.size.width))
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
      if let pin = pin(at: point), pin.pinID == pressedPin.pinID {
        click(pin)
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

  /// Nil for the pointer gone.
  private func hover(at point: CGPoint?) {
    let pinID = point.flatMap { pin(at: $0)?.pinID }
    if pinID != model.hoveredPinID {
      model.hoveredPinID = pinID
    }
    let tabID = point.flatMap { tab(at: $0)?.tabID }
    if tabID != model.hoveredTabID {
      model.hoveredTabID = tabID
    }
    let button = point.flatMap(closeButton(near:))
    if button != model.closeButton {
      model.closeButton = button
    }
  }

  /// The active pin's tab shows a close button while hovered; any other pin
  /// opens.
  private func click(_ pin: FiberPinState) {
    if pin.tabID != 0, pin.tabID == model.activeTabID {
      onClose(pin.tabID)
    } else {
      onOpenPin(pin.pinID)
    }
  }

  private func pick(_ tabID: Int) {
    if tabID != model.activeTabID {
      onSelect(tabID)
    }
  }

  // MARK: Scrolling

  /// Scrolls the list, when it's longer than the panel. Fingers can stretch
  /// it a little past either end, and it springs back when they lift; a
  /// flick coasts, and stops at the end.
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

@MainActor
@Observable
final class TabSidebarModel {
  /// The tabs the panel lists: those that aren't pins'.
  var tabs: [FiberTabState] = []
  var pins: [FiberPinState] = []
  var activeTabID = 0
  var hoveredTabID: Int?
  var hoveredPinID: String?
  var pinDrag: PinDrag?
  var pinBursts: [PinBurst] = []
  /// How many pins the panel is below (see TabSidebar.panelPins).
  var panelPinCount = 0
  var closeButton: TabCloseButton?
  /// How far the list is scrolled up the panel.
  var scrollOffset: CGFloat = 0
  /// The sidebar's size: as far as the pins and the panel can grow.
  var size: CGSize = .zero
  @ObservationIgnored var onSelect: (Int) -> Void = { _ in }
  @ObservationIgnored var onClose: (Int) -> Void = { _ in }
  @ObservationIgnored var onOpenPin: (String) -> Void = { _ in }
  @ObservationIgnored var onUnpin: (String) -> Void = { _ in }

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

  /// The panel goes while every tab is a pin's.
  var isPanelShown: Bool { !tabs.isEmpty }

  /// The pins and the space below them.
  private var pinsHeight: CGFloat {
    guard panelPinCount > 0 else {
      return 0
    }
    return PinGridLayout.height(count: panelPinCount, width: size.width)
      + PinGridLayout.listSpacing
  }

  var panelRect: CGRect {
    CGRect(
      x: 0, y: pinsHeight, width: size.width,
      height: min(
        TabListLayout.panelHeight(rows: tabs.count),
        max(size.height - pinsHeight, 0)))
  }

  var scrollRange: ClosedRange<CGFloat> {
    0...max(
      TabListLayout.panelHeight(rows: tabs.count) - (size.height - pinsHeight),
      0)
  }
}

/// Draws the tab sidebar; TabSidebar handles all input. The highlight rests
/// on the active tab and glides to the one under the pointer.
struct TabSidebarView: View {
  let model: TabSidebarModel

  var body: some View {
    let panel = model.panelRect
    ZStack(alignment: .topLeading) {
      PinGrid(model: model)

      ZStack(alignment: .top) {
        RimmedGlass(
          cornerRadius: TabListLayout.cornerRadius,
          rimWidth: TabListLayout.rimWidth
        )
        .accessibilityHidden(true)

        TabList(
          tabs: model.tabs, activeTabID: model.activeTabID,
          highlightedTabID: model.hoveredTabID ?? model.activeTabID,
          closeButton: model.closeButton, onSelect: model.onSelect,
          onClose: model.onClose
        )
        .fixedSize(horizontal: false, vertical: true)
        .offset(y: -model.scrollOffset)
        .frame(width: panel.width, height: panel.height, alignment: .top)
        .clipShape(
          RoundedRectangle(
            cornerRadius: TabListLayout.cornerRadius, style: .continuous
          )
          .inset(by: TabListLayout.rimWidth))
      }
      .frame(width: panel.width, height: panel.height)
      .scaleEffect(model.isPanelShown ? 1 : 0.9, anchor: .top)
      .opacity(model.isPanelShown ? 1 : 0)
      .offset(y: panel.minY)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Tabs")
      .accessibilityHidden(!model.isPanelShown)
    }
    // Tabs opening and closing, and pins coming and going, grow and shrink it.
    .animation(
      .spring(duration: 0.3, bounce: 0), value: model.tabs.map(\.tabID))
    .animation(.spring(duration: 0.3, bounce: 0), value: panel.minY)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain)
  }
}
