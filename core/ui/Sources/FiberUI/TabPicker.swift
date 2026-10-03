import AppKit
import FiberBridge
import SwiftUI

/// The window's most recent tabs, behind a glass bump on the window's right
/// edge that opens into a panel, which scrolls like a picker wheel, selecting
/// on lift-off. Dragging the bump moves the window. This view takes the events
/// and keeps the model; TabPickerView draws it.
@MainActor
final class TabPicker: NSView {
  /// Room for the open panel and a little past it.
  static let width = TabPickerModel.panelInset + TabListLayout.panelWidth + 40

  /// Called with the picked tab's ID, unless it's already active.
  var onSelect: (Int) -> Void = { _ in }
  /// Called with the ID of a tab whose close button was clicked. The panel
  /// stays open.
  var onClose: (Int) -> Void = { _ in }
  /// Right-clicks (or Control-clicks) on a tab, for its menu.
  var onMenu: (Int, NSEvent) -> Void = { _, _ in }

  private enum Metrics {
    /// How far in from the window's edge the pointer opens the panel and
    /// drags the window from: the bump's visible half, which the page's
    /// scrollbar keeps clear of (fiber/renderer/hooks/page_scrollbar.cc).
    static let hotZoneWidth = TabPickerModel.bumpWidth / 2
    /// How far the pointer can stray from the open panel before it closes.
    static let panelSlop: CGFloat = 24
    /// How long the pointer rests on the edge before the panel opens, so it
    /// stays shut when the pointer crosses the edge to another window.
    static let openDelay: TimeInterval = 0.07
    /// How long the pointer can be away before the panel closes.
    static let closeDelay: TimeInterval = 0.15
    /// How long the panel stays open after the pointer overshoots the bump
    /// off the window's edge, for it to come back.
    static let overshootDelay: TimeInterval = 1.5
    /// How far above or below the bump the pointer can leave and still count
    /// as overshooting it.
    static let overshootSlop: CGFloat = 24
    /// A scroll wheel (no trackpad phases) selects once it rests this long.
    static let wheelSettleDelay: TimeInterval = 0.35
    /// How far past lift-off a flick carries, in seconds of its velocity.
    static let flickProjection: CGFloat = 0.12
    /// A flick's velocity is its scrolling over this long before lift-off.
    static let flickWindow: TimeInterval = 0.1
  }

  private let model = TabPickerModel()
  /// All the window's tabs, in the tab strip's order.
  private var tabs: [FiberTabState] = []
  private var recentTabs = RecentTabs()
  private let hostingView: NSHostingView<TabPickerView>
  private var openTimer: Timer?
  private var closeTimer: Timer?
  private var wheelSettleTimer: Timer?
  /// The panel's unstretched top while the user scrolls.
  private var scrollTop: CGFloat = 0
  private var scrollSamples: [(time: TimeInterval, delta: CGFloat)] = []
  /// From the first scroll event to settling. The panel can stretch out from
  /// under the pointer meanwhile, and the rest of the gesture still comes here.
  private var isScrolling = false
  private var pressedTabID: Int?
  private var pressedCloseButtonTabID: Int?
  /// After the bump is pressed to move the window, until the pointer leaves
  /// it: the panel stays shut.
  private var isOpenHeldOff = false

  override init(frame: NSRect) {
    hostingView = NSHostingView(rootView: TabPickerView(model: model))
    super.init(frame: frame)
    hostingView.sizingOptions = []
    // The model's coordinates are the view's, title bar included.
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    model.size = bounds.size
    model.onToggle = { [weak self] in self?.toggle() }
    model.onSelect = { [weak self] tabID in self?.pick(tabID) }
    model.onClose = { [weak self] tabID in self?.onClose(tabID) }
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
    recentTabs.update(tabs, activeTabID: activeTabID)
    // The panel takes its order as it opens and keeps it, so a tab picked by
    // scrolling stays under the pointer.
    let tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.tabID, $0) })
    model.tabs = model.tabs.compactMap { tabsByID[$0.tabID] }
    model.activeTabID = activeTabID
    if tabs.isEmpty {
      close()
      return
    }
    // The tabs may have moved under the pointer, as they do when it closes
    // one.
    if model.isExpanded, !isScrolling, let window {
      let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
      if keepOpenZone.contains(point) {
        hover(at: point)
      }
    }
  }

  func close() {
    openTimer?.invalidate()
    closeTimer?.invalidate()
    isScrolling = false
    settleWheelNow()
    guard model.isExpanded else {
      return
    }
    withAnimation(.spring(duration: 0.3, bounce: 0)) {
      model.isExpanded = false
    }
    model.highlightedTabID = nil
    showCloseButton(near: nil)
  }

  // MARK: Geometry (flipped: y grows down from the window's top)

  override var isFlipped: Bool { true }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    model.size = newSize
  }

  private var hotZone: CGRect {
    let bump = model.bumpRect
    return CGRect(
      x: bounds.width - Metrics.hotZoneWidth, y: bump.minY - 8,
      width: Metrics.hotZoneWidth, height: bump.height + 16)
  }

  /// Where the pointer keeps the open panel open: around it, and between it
  /// and the window's edge.
  private var keepOpenZone: CGRect {
    let panel = model.panelRect
    let minX = panel.minX - Metrics.panelSlop
    return CGRect(
      x: minX, y: panel.minY - Metrics.panelSlop, width: bounds.width - minX,
      height: panel.height + 2 * Metrics.panelSlop)
  }

  /// The range of panel tops that keeps a tab level with `y`.
  private func panelTopRange(keepingRowAt y: CGFloat) -> ClosedRange<CGFloat> {
    let last = max(model.tabs.count - 1, 0)
    return (y - TabListLayout.rowCenter(last))...(y
      - TabListLayout.rowCenter(0))
  }

  /// The row nearest `y` were the panel's top at `top`.
  private func nearestRow(to y: CGFloat, panelTop top: CGFloat) -> Int {
    let offset = (y - top - TabListLayout.rowCenter(0))
    let row = Int((offset / TabListLayout.rowStep).rounded())
    return min(max(row, 0), model.tabs.count - 1)
  }

  private func location(of event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
  }

  /// Whether a view in front of the picker, like the omnibar or a prompt,
  /// takes `point`. The tracking area sees the pointer under it all the same.
  private func isCovered(at point: CGPoint) -> Bool {
    var view: NSView = self
    while let superview = view.superview,
      let index = superview.subviews.firstIndex(of: view)
    {
      let point = convert(point, to: superview)
      if superview.subviews[(index + 1)...].contains(where: {
        $0.hitTest(point) != nil
      }) {
        return true
      }
      view = superview
    }
    return false
  }

  // MARK: Pointer

  override func hitTest(_ point: NSPoint) -> NSView? {
    if isHidden {
      return nil
    }
    // While the panel is closed, scrolling over the bump is for the page
    // under it.
    if !model.isExpanded, NSApp.currentEvent?.type == .scrollWheel {
      return nil
    }
    let point = convert(point, from: superview)
    let area =
      isScrolling
      ? bounds : model.isExpanded ? panelHitRect.union(hotZone) : hotZone
    return area.contains(point) ? self : nil
  }

  /// The open panel and the space between it and the window's edge, where
  /// the pointer that opened it may still be.
  private var panelHitRect: CGRect {
    let panel = model.panelRect
    return CGRect(
      x: panel.minX, y: panel.minY, width: bounds.width - panel.minX,
      height: panel.height)
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
    close()
  }

  override func mouseMoved(with event: NSEvent) {
    pointerMoved(to: location(of: event))
  }

  override func mouseEntered(with event: NSEvent) {
    pointerMoved(to: location(of: event))
  }

  override func mouseExited(with event: NSEvent) {
    openTimer?.invalidate()
    let point = location(of: event)
    if isOpenHeldOff {
      isOpenHeldOff = false
    } else if overshot(to: point) {
      // The bump is thin, so the pointer aiming for it can shoot off the
      // window. Open the panel (or keep it open) for a moment so it can come
      // back to the panel instead.
      open(anchoredAt: min(max(point.y, 0), bounds.height))
      closeTimer?.invalidate()
      scheduleClose(after: Metrics.overshootDelay)
      return
    }
    if model.isExpanded {
      scheduleClose()
    }
  }

  /// Whether the pointer left the window through its right edge beside the
  /// bump or the open panel.
  private func overshot(to point: CGPoint) -> Bool {
    let zone =
      model.isExpanded
      ? keepOpenZone : hotZone.insetBy(dx: 0, dy: -Metrics.overshootSlop)
    return point.x >= bounds.width - 1 && (zone.minY...zone.maxY).contains(point.y)
  }

  override func mouseDown(with event: NSEvent) {
    let point = location(of: event)
    if hotZone.contains(point) {
      // Pressing the bump is for moving the window: the panel goes, and
      // stays shut until the pointer leaves the bump.
      close()
      isOpenHeldOff = true
      window?.performDrag(with: event)
      return
    }
    guard model.isExpanded else {
      return
    }
    if event.modifierFlags.contains(.control) {
      rightMouseDown(with: event)
      return
    }
    pressedCloseButtonTabID = closeButtonTab(at: point)
    if pressedCloseButtonTabID == nil {
      pressedTabID = tab(at: point)?.tabID
    }
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      pressedTabID = nil
      pressedCloseButtonTabID = nil
    }
    let point = location(of: event)
    guard model.isExpanded else {
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
    guard model.isExpanded, let tab = tab(at: location(of: event)) else {
      return
    }
    onMenu(tab.tabID, event)
  }

  private func pointerMoved(to point: CGPoint) {
    if model.isExpanded {
      if keepOpenZone.contains(point) {
        closeTimer?.invalidate()
        hover(at: point)
      } else {
        scheduleClose()
      }
    } else if hotZone.contains(point) {
      if !isOpenHeldOff {
        scheduleOpen()
      }
    } else {
      isOpenHeldOff = false
      openTimer?.invalidate()
    }
  }

  private func scheduleOpen() {
    guard openTimer?.isValid != true else {
      return
    }
    openTimer = Timer.scheduledTimer(
      withTimeInterval: Metrics.openDelay, repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, let window = self.window else {
          return
        }
        let point = self.convert(
          window.mouseLocationOutsideOfEventStream, from: nil)
        if self.hotZone.contains(point) {
          self.open(anchoredAt: point.y)
        }
      }
    }
  }

  private func scheduleClose(after delay: TimeInterval = Metrics.closeDelay) {
    guard closeTimer?.isValid != true else {
      return
    }
    closeTimer = Timer.scheduledTimer(
      withTimeInterval: delay, repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
  }

  /// Opens the panel with the active tab level with `y`.
  private func open(anchoredAt y: CGFloat) {
    openTimer?.invalidate()
    guard !model.isExpanded, !tabs.isEmpty,
      !isCovered(at: CGPoint(x: hotZone.midX, y: y))
    else {
      return
    }
    model.tabs = recentTabs.ordered(tabs)
    let row = model.activeRow
    model.panelTop = y - TabListLayout.rowCenter(row)
    model.highlightedTabID = model.tabs[row].tabID
    withAnimation(.spring(duration: 0.42, bounce: 0.22)) {
      model.isExpanded = true
    }
  }

  /// For accessibility, which presses the bump rather than hovering it.
  private func toggle() {
    if model.isExpanded {
      close()
    } else {
      open(anchoredAt: model.bumpRect.midY)
    }
  }

  private func tab(at point: CGPoint) -> FiberTabState? {
    let panel = model.panelRect
    guard point.x >= panel.minX, point.x <= bounds.width else {
      return nil
    }
    let offset = point.y - panel.minY - TabListLayout.contentInset
    guard offset >= 0 else {
      return nil
    }
    let row = Int(offset / TabListLayout.rowStep)
    return model.tabs.indices.contains(row) ? model.tabs[row] : nil
  }

  private func highlightRow(at point: CGPoint) {
    let tabID = tab(at: point)?.tabID
    guard tabID != model.highlightedTabID else {
      return
    }
    model.highlightedTabID = tabID
  }

  private func hover(at point: CGPoint) {
    highlightRow(at: point)
    showCloseButton(near: point)
  }

  private func closeButton(near point: CGPoint) -> TabCloseButton? {
    let panel = model.panelRect
    return TabListLayout.closeButton(
      near: CGPoint(x: point.x - panel.minX, y: point.y - panel.minY),
      in: model.tabs, width: panel.width)
  }

  /// Nil hides the close button.
  private func showCloseButton(near point: CGPoint?) {
    let button = point.flatMap(closeButton(near:))
    if button != model.closeButton {
      model.closeButton = button
    }
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

  private func pick(_ tabID: Int) {
    if tabID != model.activeTabID {
      onSelect(tabID)
    }
    close()
  }

  // MARK: Scrolling

  override func scrollWheel(with event: NSEvent) {
    guard model.isExpanded, !model.tabs.isEmpty else {
      return
    }
    // Rows pass under the pointer; their close buttons would flicker by.
    showCloseButton(near: nil)
    if event.hasPreciseScrollingDeltas {
      trackpadScroll(event)
    } else {
      wheelScroll(event)
    }
  }

  /// Moves the panel with the fingers, and on lift-off settles on the tab
  /// nearest the pointer (carried a little further by a flick) and selects it.
  private func trackpadScroll(_ event: NSEvent) {
    // The panel settles at lift-off; it doesn't coast.
    guard event.momentumPhase.isEmpty else {
      return
    }
    let point = location(of: event)
    switch event.phase {
    case .mayBegin:
      wheelSettleTimer?.invalidate()
    case .began, .changed:
      // A gesture that began over the page picks up from here.
      if event.phase == .began || !isScrolling {
        isScrolling = true
        scrollTop = model.panelTop
        scrollSamples = []
      }
      scrollBy(event, at: point)
    case .ended, .cancelled:
      if isScrolling {
        settle(at: point)
      }
    case []:
      // A precise device without phases: settle once it stops.
      isScrolling = true
      scrollTop = model.panelTop
      scrollBy(event, at: point)
      scheduleWheelSettle { [weak self] in self?.settle(at: point) }
    default:
      break
    }
  }

  private func scrollBy(_ event: NSEvent, at point: CGPoint) {
    scrollTop += event.scrollingDeltaY
    scrollSamples.append((event.timestamp, event.scrollingDeltaY))
    scrollSamples.removeAll {
      event.timestamp - $0.time > Metrics.flickWindow
    }
    model.panelTop = TabListLayout.rubberBand(
      scrollTop, in: panelTopRange(keepingRowAt: point.y))
    // A tick on the trackpad as each tab comes under the pointer.
    let previous = model.highlightedTabID
    highlightRow(at: point)
    if model.highlightedTabID != previous, model.highlightedTabID != nil {
      NSHapticFeedbackManager.defaultPerformer.perform(
        .alignment, performanceTime: .now)
    }
  }

  private func settle(at point: CGPoint) {
    // Over the window up to now, not up to the last sample: fingers resting
    // before lift-off send no events, and shouldn't flick.
    let now = ProcessInfo.processInfo.systemUptime
    let velocity =
      scrollSamples
      .filter { now - $0.time <= Metrics.flickWindow }
      .reduce(0) { $0 + $1.delta } / Metrics.flickWindow
    isScrolling = false
    scrollSamples = []
    // Past either end, this springs back to the first or last tab.
    let range = panelTopRange(keepingRowAt: point.y)
    let projected = min(
      max(model.panelTop + velocity * Metrics.flickProjection,
        range.lowerBound), range.upperBound)
    select(row: nearestRow(to: point.y, panelTop: projected), levelWith: point.y)
  }

  /// A notched wheel moves one tab per notch, and selects once it rests.
  private func wheelScroll(_ event: NSEvent) {
    guard event.scrollingDeltaY != 0 else {
      return
    }
    let point = location(of: event)
    let current =
      model.tabs.firstIndex { $0.tabID == model.highlightedTabID }
      ?? nearestRow(to: point.y, panelTop: model.panelTop)
    let row = min(
      max(current + (event.scrollingDeltaY > 0 ? -1 : 1), 0),
      model.tabs.count - 1)
    withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
      model.panelTop = point.y - TabListLayout.rowCenter(row)
    }
    model.highlightedTabID = model.tabs[row].tabID
    scheduleWheelSettle { [weak self] in
      self?.select(row: row, levelWith: point.y)
    }
  }

  private var wheelSettle: (() -> Void)?

  private func scheduleWheelSettle(_ settle: @escaping () -> Void) {
    wheelSettle = settle
    wheelSettleTimer?.invalidate()
    wheelSettleTimer = Timer.scheduledTimer(
      withTimeInterval: Metrics.wheelSettleDelay, repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.settleWheelNow() }
    }
  }

  private func settleWheelNow() {
    wheelSettleTimer?.invalidate()
    let settle = wheelSettle
    wheelSettle = nil
    settle?()
  }

  /// Slides the panel so `row` is level with `y`, and selects its tab.
  private func select(row: Int, levelWith y: CGFloat) {
    guard model.tabs.indices.contains(row) else {
      return
    }
    let tabID = model.tabs[row].tabID
    withAnimation(.spring(duration: 0.35, bounce: 0.18)) {
      model.panelTop = y - TabListLayout.rowCenter(row)
    }
    model.highlightedTabID = tabID
    if tabID != model.activeTabID {
      onSelect(tabID)
    }
  }
}

@MainActor
@Observable
final class TabPickerModel {
  /// The panel's tabs, as RecentTabs ordered them when it opened.
  var tabs: [FiberTabState] = []
  var activeTabID = 0
  var isExpanded = false
  /// The open panel's top, in the picker's (flipped) coordinates.
  var panelTop: CGFloat = 0
  /// The tab under the pointer, or where scrolling has brought the panel.
  var highlightedTabID: Int?
  var closeButton: TabCloseButton?
  /// The picker's size, which places the bump.
  var size: CGSize = .zero
  @ObservationIgnored var onToggle: () -> Void = {}
  @ObservationIgnored var onSelect: (Int) -> Void = { _ in }
  @ObservationIgnored var onClose: (Int) -> Void = { _ in }

  /// The bump is a capsule this wide, centered on the window's edge.
  nonisolated static let bumpWidth: CGFloat = 16
  static let panelInset: CGFloat = 10

  /// A capsule centered on the window's edge, a third of its height.
  var bumpRect: CGRect {
    let height = max(size.height / 3, 60)
    return CGRect(
      x: size.width - Self.bumpWidth / 2, y: ((size.height - height) / 2).rounded(),
      width: Self.bumpWidth, height: height)
  }

  var activeRow: Int {
    tabs.firstIndex { $0.tabID == activeTabID } ?? 0
  }

  var panelRect: CGRect {
    CGRect(
      x: size.width - Self.panelInset - TabListLayout.panelWidth, y: panelTop,
      width: TabListLayout.panelWidth,
      height: TabListLayout.panelHeight(rows: tabs.count))
  }
}

/// Orders a window's tabs for the tab picker: the active tab, then the rest
/// by when each was last active, as many as are easy to keep in mind.
struct RecentTabs {
  static let limit = 15

  private var activeTabID: Int?
  /// When each tab stopped being the active one. Chrome's last active time is
  /// when a tab was last shown or opened, so a tab opened in the background
  /// would otherwise pass the one it was opened from once that's left.
  private var leftTimes: [Int: Date] = [:]

  mutating func update(
    _ tabs: [FiberTabState], activeTabID: Int, now: Date = .now
  ) {
    guard activeTabID != self.activeTabID else {
      return
    }
    if let previous = self.activeTabID {
      leftTimes[previous] = now
      let tabIDs = Set(tabs.map(\.tabID))
      leftTimes = leftTimes.filter { tabIDs.contains($0.key) }
    }
    self.activeTabID = activeTabID
  }

  func ordered(_ tabs: [FiberTabState]) -> [FiberTabState] {
    Array(tabs.sorted { lastActive($0) > lastActive($1) }.prefix(Self.limit))
  }

  private func lastActive(_ tab: FiberTabState) -> Date {
    tab.tabID == activeTabID
      ? .distantFuture : leftTimes[tab.tabID] ?? tab.lastActiveTime
  }
}
