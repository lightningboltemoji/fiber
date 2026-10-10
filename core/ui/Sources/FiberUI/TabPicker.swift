import AppKit
import FiberBridge
import SwiftUI

/// The window's recent tabs, behind a glass lip on its top edge that opens
/// into a strip, which scrolls like a picker wheel, selecting on lift-off, with
/// the highlighted tab's page below. Dragging the lip moves the window. This
/// view takes the events and keeps the model; TabPickerView draws it.
@MainActor
final class TabPicker: NSView {
  /// Room from the window's top for the open strip and preview, and a little
  /// past them.
  static let height =
    TabPickerModel.panelInset + TabPickerLayout.panelHeight
    + TabPickerModel.previewGap + TabPickerLayout.previewSize.height + 40

  /// Called with the picked tab's ID, unless it's already active.
  var onSelect: (Int) -> Void = { _ in }
  /// Called with the ID of a tab whose close button was clicked. The strip
  /// stays open.
  var onClose: (Int) -> Void = { _ in }
  /// Right-clicks (or Control-clicks) on a tab, for its menu.
  var onMenu: (Int, NSEvent) -> Void = { _, _ in }
  /// A tab's page as it was last seen, if the browser has it.
  var preview: (Int) -> NSImage? = { _ in nil }

  private enum Metrics {
    /// How far down from the window's edge the pointer opens the strip and
    /// drags the window from: the lip's visible half.
    static let hotZoneHeight = TabPickerModel.lipHeight / 2
    /// How far the pointer can stray from the open strip before it closes.
    static let panelSlop: CGFloat = 24
    /// How long the pointer rests on the edge before the strip opens, so it
    /// stays shut when the pointer crosses the edge to the menu bar.
    static let openDelay: TimeInterval = 0.07
    /// How long the pointer can be away before the strip closes.
    static let closeDelay: TimeInterval = 0.15
    /// How long the strip stays open after the pointer overshoots the lip
    /// off the window's edge, for it to come back.
    static let overshootDelay: TimeInterval = 1.5
    /// How far beside the lip the pointer can leave and still count as
    /// overshooting it.
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
  private var wheelSettle: (() -> Void)?
  /// The strip's unstretched left edge while the user scrolls.
  private var scrollLeft: CGFloat = 0
  private var scrollSamples: [(time: TimeInterval, delta: CGFloat)] = []
  /// From the first scroll event to settling. The strip can stretch out from
  /// under the pointer meanwhile, and the rest of the gesture still comes here.
  private var isScrolling = false
  private var pressedTabID: Int?
  private var pressedCloseButtonTabID: Int?
  /// After the lip is pressed to move the window, until the pointer leaves
  /// it: the strip stays shut.
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
    // The strip takes its order as it opens and keeps it, so a tab picked by
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
    withAnimation(.spring(duration: 0.3, bounce: 0).slowMotion) {
      model.isExpanded = false
    }
    highlight(nil)
    showCloseButton(near: nil)
  }

  // MARK: Geometry (flipped: y grows down from the window's top)

  override var isFlipped: Bool { true }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    model.size = newSize
  }

  private var hotZone: CGRect {
    let lip = model.lipRect
    return CGRect(
      x: lip.minX - 8, y: 0, width: lip.width + 16,
      height: Metrics.hotZoneHeight)
  }

  /// Where the pointer keeps the open strip open: around it and its preview,
  /// and between it and the window's edge.
  private var keepOpenZone: CGRect {
    let panel = model.panelRect.insetBy(
      dx: -Metrics.panelSlop, dy: -Metrics.panelSlop)
    let zone = CGRect(
      x: panel.minX, y: 0, width: panel.width, height: panel.maxY)
    guard let preview = model.previewRect else {
      return zone
    }
    return zone.union(
      preview.insetBy(dx: -Metrics.panelSlop, dy: -Metrics.panelSlop))
  }

  /// The open strip, the space between it and the window's edge, where the
  /// pointer that opened it may still be, and the preview.
  private var panelHitRect: CGRect {
    let panel = model.panelRect
    let rect = CGRect(
      x: panel.minX, y: 0, width: panel.width, height: panel.maxY)
    return model.previewRect.map(rect.union) ?? rect
  }

  /// The range of strip lefts that keeps a tab under `x`.
  private func panelLeftRange(keepingItemAt x: CGFloat) -> ClosedRange<CGFloat>
  {
    let last = max(model.tabs.count - 1, 0)
    return (x - TabPickerLayout.itemCenterX(last))...(x
      - TabPickerLayout.itemCenterX(0))
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
    // While the strip is closed, scrolling over the lip is for the page
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
      // The lip is thin, so the pointer aiming for it can shoot off the
      // window. Open the strip (or keep it open) for a moment so it can come
      // back to it instead.
      open(anchoredAt: min(max(point.x, 0), bounds.width))
      closeTimer?.invalidate()
      scheduleClose(after: Metrics.overshootDelay)
      return
    }
    if model.isExpanded {
      scheduleClose()
    }
  }

  /// Whether the pointer left the window through its top edge beside the lip
  /// or the open strip.
  private func overshot(to point: CGPoint) -> Bool {
    let zone =
      model.isExpanded
      ? keepOpenZone : hotZone.insetBy(dx: -Metrics.overshootSlop, dy: 0)
    return point.y <= 1 && (zone.minX...zone.maxX).contains(point.x)
  }

  override func mouseDown(with event: NSEvent) {
    let point = location(of: event)
    if hotZone.contains(point) {
      // Pressing the lip is for moving the window: the strip goes, and stays
      // shut until the pointer leaves the lip.
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
          self.open(anchoredAt: point.x)
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

  /// Opens the strip with the active tab under `x`, highlighted.
  private func open(anchoredAt x: CGFloat) {
    openTimer?.invalidate()
    guard !model.isExpanded, !tabs.isEmpty,
      !isCovered(at: CGPoint(x: x, y: hotZone.midY))
    else {
      return
    }
    model.tabs = recentTabs.ordered(tabs)
    model.previews = [:]
    let index = model.activeIndex
    model.panelLeft = x - TabPickerLayout.itemCenterX(index)
    highlight(model.tabs[index].tabID)
    withAnimation(.spring(duration: 0.42, bounce: 0.22).slowMotion) {
      model.isExpanded = true
    }
  }

  /// For accessibility, which presses the lip rather than hovering it.
  private func toggle() {
    if model.isExpanded {
      close()
    } else {
      open(anchoredAt: model.lipRect.midX)
    }
  }

  /// The tab across from `point`, between the strip's bottom and the window's
  /// edge; over the preview, the one it shows.
  private func index(at point: CGPoint) -> Int? {
    if let preview = model.previewRect, preview.contains(point) {
      return model.highlightedIndex
    }
    guard point.y <= model.panelRect.maxY else {
      return nil
    }
    return TabPickerLayout.index(
      atX: point.x - model.panelLeft, count: model.tabs.count)
  }

  private func tab(at point: CGPoint) -> FiberTabState? {
    index(at: point).map { model.tabs[$0] }
  }

  private func tab(atX x: CGFloat) -> FiberTabState? {
    TabPickerLayout.index(atX: x - model.panelLeft, count: model.tabs.count)
      .map { model.tabs[$0] }
  }

  /// Highlights a tab, fetching its preview the first time it's highlighted
  /// while the strip is open.
  private func highlight(_ tabID: Int?) {
    guard tabID != model.highlightedTabID else {
      return
    }
    model.highlightedTabID = tabID
    if let tabID, tabID != model.activeTabID, model.previews[tabID] == nil {
      model.previews[tabID] = .some(preview(tabID))
    }
  }

  private func hover(at point: CGPoint) {
    highlight(tab(at: point)?.tabID)
    showCloseButton(near: point)
  }

  private func closeButton(near point: CGPoint) -> TabCloseButton? {
    let panel = model.panelRect
    guard panel.contains(point), let index = index(at: point) else {
      return nil
    }
    let button = TabPickerLayout.closeButtonRect(index)
      .offsetBy(dx: panel.minX, dy: panel.minY)
    return TabCloseButton(
      tabID: model.tabs[index].tabID, isHovered: button.contains(point))
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
    // Tabs pass under the pointer; their close buttons would flicker by.
    showCloseButton(near: nil)
    if event.hasPreciseScrollingDeltas {
      trackpadScroll(event)
    } else {
      wheelScroll(event)
    }
  }

  /// Either way across the trackpad moves the strip along: left and up both
  /// bring older tabs under the pointer.
  private static func delta(of event: NSEvent) -> CGFloat {
    event.scrollingDeltaX + event.scrollingDeltaY
  }

  /// Moves the strip with the fingers, and on lift-off settles on the tab
  /// nearest the pointer (carried a little further by a flick) and selects it.
  private func trackpadScroll(_ event: NSEvent) {
    // The strip settles at lift-off; it doesn't coast.
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
        scrollLeft = model.panelLeft
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
      scrollLeft = model.panelLeft
      scrollBy(event, at: point)
      scheduleWheelSettle { [weak self] in self?.settle(at: point) }
    default:
      break
    }
  }

  private func scrollBy(_ event: NSEvent, at point: CGPoint) {
    let delta = Self.delta(of: event)
    scrollLeft += delta
    scrollSamples.append((event.timestamp, delta))
    scrollSamples.removeAll {
      event.timestamp - $0.time > Metrics.flickWindow
    }
    model.panelLeft = TabListLayout.rubberBand(
      scrollLeft, in: panelLeftRange(keepingItemAt: point.x))
    // A tick on the trackpad as each tab comes under the pointer.
    let previous = model.highlightedTabID
    highlight(tab(atX: point.x)?.tabID)
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
    let range = panelLeftRange(keepingItemAt: point.x)
    let projected = min(
      max(model.panelLeft + velocity * Metrics.flickProjection,
        range.lowerBound), range.upperBound)
    select(
      index: TabPickerLayout.nearestIndex(
        toX: point.x - projected, count: model.tabs.count),
      under: point.x)
  }

  /// A notched wheel moves one tab per notch, and selects once it rests.
  private func wheelScroll(_ event: NSEvent) {
    let delta = Self.delta(of: event)
    guard delta != 0 else {
      return
    }
    let point = location(of: event)
    let current =
      model.highlightedIndex
      ?? TabPickerLayout.nearestIndex(
        toX: point.x - model.panelLeft, count: model.tabs.count)
    let index = min(
      max(current + (delta > 0 ? -1 : 1), 0), model.tabs.count - 1)
    withAnimation(.spring(duration: 0.25, bounce: 0.1).slowMotion) {
      model.panelLeft = point.x - TabPickerLayout.itemCenterX(index)
    }
    highlight(model.tabs[index].tabID)
    scheduleWheelSettle { [weak self] in
      self?.select(index: index, under: point.x)
    }
  }

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

  /// Slides the strip so tab `index` is under `x`, and selects it.
  private func select(index: Int, under x: CGFloat) {
    guard model.tabs.indices.contains(index) else {
      return
    }
    let tabID = model.tabs[index].tabID
    withAnimation(.spring(duration: 0.35, bounce: 0.18).slowMotion) {
      model.panelLeft = x - TabPickerLayout.itemCenterX(index)
    }
    highlight(tabID)
    if tabID != model.activeTabID {
      onSelect(tabID)
    }
  }
}

@MainActor
@Observable
final class TabPickerModel {
  /// The strip's tabs, as RecentTabs ordered them when it opened.
  var tabs: [FiberTabState] = []
  var activeTabID = 0
  var isExpanded = false
  /// The open strip's left edge, in the picker's coordinates.
  var panelLeft: CGFloat = 0
  /// The tab under the pointer, or where scrolling has brought the strip.
  var highlightedTabID: Int?
  var closeButton: TabCloseButton?
  /// The picker's size, which places the lip.
  var size: CGSize = .zero
  /// The previews fetched since the strip opened, by tab ID, nil for a tab
  /// without one.
  var previews: [Int: NSImage?] = [:]
  @ObservationIgnored var onToggle: () -> Void = {}
  @ObservationIgnored var onSelect: (Int) -> Void = { _ in }
  @ObservationIgnored var onClose: (Int) -> Void = { _ in }

  /// The lip is a capsule this tall, centered on the window's top edge.
  nonisolated static let lipHeight: CGFloat = 16
  /// From the window's top edge to the open strip.
  nonisolated static let panelInset: CGFloat = 10
  nonisolated static let previewGap: CGFloat = 8
  /// The least room kept beside the preview.
  static let margin: CGFloat = 16

  /// A capsule centered on the window's top edge, a third of its width.
  var lipRect: CGRect {
    let width = max(size.width / 3, 120)
    return CGRect(
      x: ((size.width - width) / 2).rounded(), y: -Self.lipHeight / 2,
      width: width, height: Self.lipHeight)
  }

  var panelRect: CGRect {
    CGRect(
      x: panelLeft, y: Self.panelInset,
      width: TabPickerLayout.panelWidth(count: tabs.count),
      height: TabPickerLayout.panelHeight)
  }

  var activeIndex: Int {
    tabs.firstIndex { $0.tabID == activeTabID } ?? 0
  }

  var highlightedIndex: Int? {
    tabs.firstIndex { $0.tabID == highlightedTabID }
  }

  /// The highlighted tab's preview: not the active tab's, whose page is
  /// showing.
  var preview: NSImage? {
    guard let tabID = highlightedTabID, tabID != activeTabID else {
      return nil
    }
    return previews[tabID] ?? nil
  }

  /// Under the highlighted tab, as far as the window allows, while it has a
  /// preview.
  var previewRect: CGRect? {
    guard isExpanded, preview != nil, let index = highlightedIndex else {
      return nil
    }
    let size = TabPickerLayout.previewSize
    let centerX = panelLeft + TabPickerLayout.itemCenterX(index)
    let x = min(
      max(centerX - size.width / 2, Self.margin),
      self.size.width - Self.margin - size.width)
    return CGRect(
      origin: CGPoint(x: x.rounded(), y: panelRect.maxY + Self.previewGap),
      size: size)
  }
}

/// Where the strip puts its tabs, in a row `inset` in from its edges, shared
/// by hit testing and drawing.
enum TabPickerLayout {
  static let itemSize = CGSize(width: 180, height: 44)
  static let spacing: CGFloat = 2
  static let inset: CGFloat = 10
  static let cornerRadius = TabListLayout.cornerRadius
  static let rimWidth = TabListLayout.rimWidth
  static var panelHeight: CGFloat { 2 * inset + itemSize.height }
  static var step: CGFloat { itemSize.width + spacing }
  /// A tab's close button is a square this wide at its right end.
  static let closeButtonSize: CGFloat = 24
  static let closeButtonInset: CGFloat = 6
  static let thumbnailSize = CGSize(width: 288, height: 180)
  /// The preview's glass, around the page's thumbnail.
  static let previewInset: CGFloat = 10
  static var previewSize: CGSize {
    CGSize(
      width: thumbnailSize.width + 2 * previewInset,
      height: thumbnailSize.height + 2 * previewInset)
  }

  static func panelWidth(count: Int) -> CGFloat {
    2 * inset + CGFloat(max(count, 1)) * step - spacing
  }

  /// From the strip's top-left.
  static func itemFrame(_ index: Int) -> CGRect {
    CGRect(
      origin: CGPoint(x: inset + CGFloat(index) * step, y: inset),
      size: itemSize)
  }

  static func itemCenterX(_ index: Int) -> CGFloat {
    inset + CGFloat(index) * step + itemSize.width / 2
  }

  /// The tab across from `x`, from the strip's left edge.
  static func index(atX x: CGFloat, count: Int) -> Int? {
    let offset = x - inset
    guard offset >= 0 else {
      return nil
    }
    let index = Int(offset / step)
    return index < count ? index : nil
  }

  static func nearestIndex(toX x: CGFloat, count: Int) -> Int {
    let index = Int(((x - itemCenterX(0)) / step).rounded())
    return min(max(index, 0), count - 1)
  }

  /// From the strip's top-left.
  static func closeButtonRect(_ index: Int) -> CGRect {
    let item = itemFrame(index)
    return CGRect(
      x: item.maxX - closeButtonInset - closeButtonSize,
      y: item.midY - closeButtonSize / 2, width: closeButtonSize,
      height: closeButtonSize)
  }
}

/// Orders a window's tabs for the tab picker: the active tab, then the rest
/// by when each was last active, as many as are easy to keep in mind.
struct RecentTabs {
  static let limit = 10

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
