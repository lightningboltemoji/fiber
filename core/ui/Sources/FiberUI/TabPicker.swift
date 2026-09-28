import AppKit
import FiberBridge
import SwiftUI

/// The window's tabs, behind the gutter along the page's right edge (see
/// PageGutter). Hovering anywhere in the gutter opens a glass panel out of
/// it, listing the tabs, placed so the active tab is level with the pointer;
/// dragging the gutter moves the window. Scrolling moves the panel under the
/// pointer like a picker wheel, and lifting off selects the tab it settles
/// on; clicking a tab selects it too. While the toolbar shows, its sidebar
/// (TabSidebar) lists the tabs instead, and the gutter only moves the window.
///
/// This view takes the pointer and scroll events and keeps the model;
/// TabPickerView draws it. It fills the window's height along its right
/// edge, but only the gutter (and the open panel) takes clicks.
@MainActor
final class TabPicker: NSView {
  /// Room for the open panel and a little past it.
  static let width = TabPickerModel.panelInset + TabListLayout.panelWidth + 40

  /// Called when the user picks a tab.
  var onSelect: (Int) -> Void = { _ in }

  /// Whether the gutter opens the panel. Turning it off closes the panel.
  var isPanelEnabled: Bool {
    get { model.isPanelEnabled }
    set {
      model.isPanelEnabled = newValue
      if !newValue {
        close()
      }
    }
  }

  private enum Metrics {
    /// How far the pointer can stray from the open panel before it closes.
    static let panelSlop: CGFloat = 24
    /// How long the pointer rests on the edge before the panel opens, so it
    /// stays shut when the pointer crosses the edge to another window.
    static let openDelay: TimeInterval = 0.07
    /// How long the pointer can be away before the panel closes.
    static let closeDelay: TimeInterval = 0.15
    /// How long the panel stays open after the pointer overshoots the gutter
    /// or the panel off the window's edge, for it to come back.
    static let overshootDelay: TimeInterval = 0.75
    /// A scroll wheel (no trackpad phases) selects once it rests this long.
    static let wheelSettleDelay: TimeInterval = 0.35
    /// How far past lift-off a flick carries, in seconds of its velocity.
    static let flickProjection: CGFloat = 0.12
    /// A flick's velocity is its scrolling over this long before lift-off.
    static let flickWindow: TimeInterval = 0.1
  }

  private let model = TabPickerModel()
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
  /// After the gutter is pressed to move the window, until the pointer leaves
  /// the gutter: the panel stays shut.
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
    model.tabs = tabs
    model.activeTabID = activeTabID
    if tabs.isEmpty {
      close()
    }
  }

  /// Closes the panel back into the gutter.
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
  }

  // MARK: Geometry (flipped: y grows down from the window's top)

  override var isFlipped: Bool { true }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    model.size = newSize
  }

  /// Where the pointer opens the panel: the gutter the page stops short of,
  /// so the page keeps all of itself.
  private var hotZone: CGRect { model.gutterRect }

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

  // MARK: Pointer

  override func hitTest(_ point: NSPoint) -> NSView? {
    if isHidden {
      return nil
    }
    // While the panel is closed, scrolling over the gutter is for the page
    // (the gutter passes it on).
    if !model.isExpanded, NSApp.currentEvent?.type == .scrollWheel {
      return nil
    }
    let point = convert(point, from: superview)
    let area =
      isScrolling
      ? bounds : model.isExpanded ? panelHitRect.union(hotZone) : hotZone
    return area.contains(point) ? self : nil
  }

  /// The open panel and the gutter between it and the window's edge, where
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
      // The gutter is thin, so the pointer aiming for it can shoot off the
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

  /// Whether the pointer left the window through its right edge: across the
  /// gutter, or beside the open panel.
  private func overshot(to point: CGPoint) -> Bool {
    point.x >= bounds.width - 1 && (0...bounds.height).contains(point.y)
  }

  override func mouseDown(with event: NSEvent) {
    let point = location(of: event)
    if hotZone.contains(point) {
      // Pressing the gutter is for moving the window: the panel goes, and
      // stays shut until the pointer leaves the gutter.
      close()
      isOpenHeldOff = true
      window?.performDrag(with: event)
      return
    }
    guard model.isExpanded else {
      return
    }
    pressedTabID = tab(at: point)?.tabID
  }

  override func mouseUp(with event: NSEvent) {
    defer { pressedTabID = nil }
    guard model.isExpanded, let tabID = tab(at: location(of: event))?.tabID,
      tabID == pressedTabID
    else {
      return
    }
    pick(tabID)
  }

  private func pointerMoved(to point: CGPoint) {
    if model.isExpanded {
      if keepOpenZone.contains(point) {
        closeTimer?.invalidate()
        highlightRow(at: point)
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
    guard model.isPanelEnabled, !model.isExpanded, !model.tabs.isEmpty else {
      return
    }
    let row = model.activeRow
    model.panelTop = y - TabListLayout.rowCenter(row)
    model.highlightedTabID = model.tabs[row].tabID
    withAnimation(.spring(duration: 0.42, bounce: 0.22)) {
      model.isExpanded = true
    }
  }

  /// For accessibility, which can't hover the gutter.
  private func toggle() {
    if model.isExpanded {
      close()
    } else {
      open(anchoredAt: model.gutterRect.midY)
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

  /// Highlights the tab under `point`.
  private func highlightRow(at point: CGPoint) {
    let tabID = tab(at: point)?.tabID
    guard tabID != model.highlightedTabID else {
      return
    }
    model.highlightedTabID = tabID
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
  var tabs: [FiberTabState] = []
  var activeTabID = 0
  var isExpanded = false
  /// Whether the gutter opens the panel (see TabPicker.isPanelEnabled).
  var isPanelEnabled = true
  /// The open panel's top, in the picker's (flipped) coordinates.
  var panelTop: CGFloat = 0
  /// The tab under the pointer, or where scrolling has brought the panel.
  var highlightedTabID: Int?
  /// The picker's size, which places the gutter.
  var size: CGSize = .zero
  @ObservationIgnored var onToggle: () -> Void = {}
  @ObservationIgnored var onSelect: (Int) -> Void = { _ in }

  static let panelInset: CGFloat = 10

  /// The page's gutter, the window's height along its right edge.
  var gutterRect: CGRect {
    CGRect(
      x: size.width - PageGutter.width, y: 0, width: PageGutter.width,
      height: size.height)
  }

  /// The active tab's row.
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
