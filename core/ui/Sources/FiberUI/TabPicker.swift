import AppKit
import FiberBridge
import SwiftUI

/// The window's recent tabs, behind a glass lip on its top edge. The lip
/// swells toward the pointer as it comes near, and once the pointer rests on
/// it, drips into a column showing the active tab, which pours down a tab
/// ahead of the pointer as it moves lower, with the highlighted tab's page
/// beside it. Scrolling moves the highlight, selecting on lift-off. Dragging
/// the lip moves the window. This view takes the events, keeps the model and
/// runs the drop's springs; TabPickerView draws it.
@MainActor
final class TabPicker: NSView {
  /// Called with the picked tab's ID, unless it's already active.
  var onSelect: (Int) -> Void = { _ in }
  /// Called with the ID of a tab whose close button was clicked. The column
  /// stays open.
  var onClose: (Int) -> Void = { _ in }
  /// Right-clicks (or Control-clicks) on a tab, for its menu.
  var onMenu: (Int, NSEvent) -> Void = { _, _ in }
  /// A tab's page as it was last seen, if the browser has it.
  var preview: (Int) -> NSImage? = { _ in nil }

  private enum Metrics {
    /// How far down from the window's edge the pointer opens the column and
    /// drags the window from: the lip's visible half.
    static let hotZoneHeight = TabPickerModel.lipHeight / 2
    /// How near the lip the pointer comes for it to swell toward it.
    static let leanReach: CGFloat = 28
    /// The bead the lip swells into, and how far it sags with the pointer on
    /// the edge. It has no depth, so it has no corners, just the sag.
    static let beadWidth: CGFloat = 88
    static let beadSwell: CGFloat = 5
    /// How far the pointer can stray from the open column before it closes.
    static let panelSlop: CGFloat = 24
    /// How long the pointer rests on the edge before the column opens, so
    /// it stays shut when the pointer crosses the edge to the menu bar.
    static let openDelay: TimeInterval = 0.07
    /// How long the pointer can be away before the column closes.
    static let closeDelay: TimeInterval = 0.15
    /// How long the column stays open after the pointer overshoots the lip
    /// off the window's edge, for it to come back.
    static let overshootDelay: TimeInterval = 1.5
    /// How far beside the lip the pointer can leave and still count as
    /// overshooting it.
    static let overshootSlop: CGFloat = 24
    /// A scroll wheel (no trackpad phases) selects once it rests this long.
    static let wheelSettleDelay: TimeInterval = 0.35
    /// How far a trackpad scrolls to move the highlight a tab.
    static let scrollStep: CGFloat = 18
  }

  private let model = TabPickerModel()
  /// All the window's tabs, in the tab strip's order.
  private var tabs: [FiberTabState] = []
  private var recentTabs = RecentTabs()
  private let hostingView: NSHostingView<TabPickerView>
  private var motion = TabPickerDropMotion(
    at: .init(
      lipMinX: 0, lipMaxX: 0, bodyMidX: 0, bodyWidth: Metrics.beadWidth,
      depth: 0, bulgeX: 0))
  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval?
  /// The pointer near the lip while the column is shut, which the lip swells
  /// toward.
  private var leanPoint: CGPoint?
  /// Where the pointer last was across the open column, which the drop's
  /// leading edge sags toward as it pours.
  private var pourX: CGFloat?
  private var openTimer: Timer?
  private var closeTimer: Timer?
  private var wheelSettleTimer: Timer?
  private var wheelSettle: (() -> Void)?
  /// Trackpad scrolling not yet enough to move the highlight.
  private var scrollTravel: CGFloat = 0
  /// From the first scroll event to settling. The rest of the gesture comes
  /// here wherever the pointer is.
  private var isScrolling = false
  private var pressedTabID: Int?
  private var pressedCloseButtonTabID: Int?
  /// After the lip is pressed to move the window, until the pointer leaves
  /// it: the column stays shut.
  private var isOpenHeldOff = false
  /// How many tabs the glass has poured over far enough to show.
  private var shownCount = 0

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
    // The column takes its order as it opens and keeps it, so tabs don't
    // move under the pointer. Those after a closed one close up.
    let tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.tabID, $0) })
    withAnimation(
      model.isExpanded ? .spring(duration: 0.3, bounce: 0.15).slowMotion : nil
    ) {
      model.tabs = model.tabs.compactMap { tabsByID[$0.tabID] }
    }
    model.activeTabID = activeTabID
    if tabs.isEmpty {
      close()
      return
    }
    guard model.isExpanded else {
      return
    }
    model.revealedCount = min(model.revealedCount, model.maxRows)
    animate()
    // The tabs may have moved under the pointer, as they do when it closes
    // one.
    if !isScrolling, let window {
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
    // The highlight stays, to draw back up into the lip with its tab.
    model.isExpanded = false
    model.revealedCount = 0
    showCloseButton(near: nil)
    animate()
  }

  // MARK: Geometry (flipped: y grows down from the window's top)

  override var isFlipped: Bool { true }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    model.size = newSize
    if model.isExpanded {
      model.revealedCount = min(model.revealedCount, model.maxRows)
    }
    if displayLink == nil {
      motion.target = dropTarget
      motion.snap()
      model.drop = motion.drop
    } else {
      motion.target = dropTarget
    }
  }

  private var hotZone: CGRect {
    let lip = model.lipRect
    return CGRect(
      x: lip.minX - 8, y: 0, width: lip.width + 16,
      height: Metrics.hotZoneHeight)
  }

  /// The column down to `rows` tabs, from the window's edge.
  private func columnRect(rows: Int) -> CGRect {
    CGRect(
      x: model.columnMinX, y: 0, width: TabPickerLayout.columnWidth,
      height: TabPickerLayout.columnBottom(rows: rows))
  }

  /// Where the pointer keeps the open column open: around it and a tab
  /// further, which the pointer pours it down to, and around the preview.
  private var keepOpenZone: CGRect {
    let column = columnRect(rows: min(model.revealedCount + 1, model.maxRows))
      .insetBy(dx: -Metrics.panelSlop, dy: -Metrics.panelSlop)
    guard let preview = model.previewRect else {
      return column
    }
    return column.union(
      preview.insetBy(dx: -Metrics.panelSlop, dy: -Metrics.panelSlop))
  }

  /// The open column and the preview.
  private var panelHitRect: CGRect {
    let column = columnRect(rows: model.revealedCount)
    return model.previewRect.map(column.union) ?? column
  }

  /// Where the drop is headed: the open column down to the tabs revealed,
  /// or the lip, swelling toward the pointer near it.
  private var dropTarget: TabPickerDropMotion.Target {
    let lip = model.lipRect
    let halfHeight = TabPickerModel.lipHeight / 2
    if model.isExpanded {
      let width = TabPickerLayout.columnWidth
      let neck = TabPickerLayout.filletRadius + halfHeight
      return .init(
        lipMinX: model.columnMinX - neck,
        lipMaxX: model.columnMinX + width + neck,
        bodyMidX: model.columnMidX, bodyWidth: width,
        depth: TabPickerLayout.columnBottom(rows: model.revealedCount)
          - halfHeight,
        bulgeX: pourX ?? model.columnMidX)
    }
    // Shut, the body stays inside the lip, where it has no depth to show.
    let inset = Metrics.beadWidth / 2 + halfHeight
    let range = (lip.minX + inset)...max(lip.maxX - inset, lip.minX + inset)
    func clamped(_ x: CGFloat) -> CGFloat {
      min(max(x, range.lowerBound), range.upperBound)
    }
    let midX = clamped(leanPoint?.x ?? motion.target.bodyMidX)
    let nearness =
      leanPoint.map { 1 - min(max($0.y / Metrics.leanReach, 0), 1) } ?? 0
    return .init(
      lipMinX: lip.minX, lipMaxX: lip.maxX, bodyMidX: midX,
      bodyWidth: Metrics.beadWidth, depth: 0,
      swell: Metrics.beadSwell * nearness, bulgeX: midX)
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

  // MARK: Motion

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    stopMotion()
    guard let window else {
      return
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(windowDidResignKey(_:)),
      name: NSWindow.didResignKeyNotification, object: window)
  }

  /// Sets the drop's springs toward `dropTarget`, running them until they
  /// settle.
  private func animate() {
    motion.target = dropTarget
    guard displayLink == nil else {
      return
    }
    guard let window else {
      motion.snap()
      model.drop = motion.drop
      return
    }
    let link = window.displayLink(target: self, selector: #selector(step(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
    lastTimestamp = nil
  }

  @objc private func step(_ link: CADisplayLink) {
    let now = link.targetTimestamp
    let elapsed = now - (lastTimestamp ?? link.timestamp)
    lastTimestamp = now
    motion.step(
      CGFloat(elapsed / SlowMotion.factor),
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    if motion.isSettled {
      motion.snap()
      stopMotion()
    }
    model.drop = motion.drop
    tickForTabsShown()
  }

  /// A tick on the trackpad as each tab pops out of the glass, unless
  /// scrolling, which ticks for each tab already.
  private func tickForTabsShown() {
    let shown =
      model.isExpanded
      ? (0..<model.maxRows).prefix { model.coverage(ofRow: $0) >= 0.5 }.count
      : 0
    if shown > shownCount, !isScrolling {
      NSHapticFeedbackManager.defaultPerformer.perform(
        .alignment, performanceTime: .now)
    }
    shownCount = shown
  }

  private func stopMotion() {
    displayLink?.invalidate()
    displayLink = nil
    lastTimestamp = nil
  }

  // MARK: Pointer

  override func hitTest(_ point: NSPoint) -> NSView? {
    if isHidden {
      return nil
    }
    // While the column is shut, scrolling over the lip is for the page under
    // it.
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

  @objc private func windowDidResignKey(_ notification: Notification) {
    close()
    lean(toward: nil)
  }

  override func mouseMoved(with event: NSEvent) {
    pointerMoved(to: location(of: event))
  }

  override func mouseEntered(with event: NSEvent) {
    pointerMoved(to: location(of: event))
  }

  override func mouseExited(with event: NSEvent) {
    openTimer?.invalidate()
    lean(toward: nil)
    let point = location(of: event)
    if isOpenHeldOff {
      isOpenHeldOff = false
    } else if overshot(to: point) {
      // The lip is thin, so the pointer aiming for it can shoot off the
      // window. Open the column (or keep it open) for a moment so it can
      // come back to it instead.
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
  /// or the open column.
  private func overshot(to point: CGPoint) -> Bool {
    let zone =
      model.isExpanded
      ? keepOpenZone : hotZone.insetBy(dx: -Metrics.overshootSlop, dy: 0)
    return point.y <= 1 && (zone.minX...zone.maxX).contains(point.x)
  }

  override func mouseDown(with event: NSEvent) {
    let point = location(of: event)
    if hotZone.contains(point) {
      // Pressing the lip is for moving the window: the column goes, and
      // stays shut until the pointer leaves the lip.
      close()
      lean(toward: nil)
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
      return
    }
    lean(toward: isOpenHeldOff ? nil : point)
    if hotZone.contains(point) {
      if !isOpenHeldOff {
        scheduleOpen()
      }
    } else {
      isOpenHeldOff = false
      openTimer?.invalidate()
    }
  }

  /// Swells the shut lip toward `point`, if it's near and nothing in front
  /// of the picker is in the way.
  private func lean(toward point: CGPoint?) {
    let lip = model.lipRect
    let point = point.flatMap {
      (lip.minX...lip.maxX).contains($0.x)
        && (0...Metrics.leanReach).contains($0.y) && !isCovered(at: $0)
        ? $0 : nil
    }
    guard point != leanPoint else {
      return
    }
    leanPoint = point
    if !model.isExpanded {
      animate()
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

  /// Opens the column under `x`, showing only the active tab, highlighted.
  private func open(anchoredAt x: CGFloat) {
    openTimer?.invalidate()
    guard !model.isExpanded, !tabs.isEmpty,
      !isCovered(at: CGPoint(x: x, y: hotZone.midY))
    else {
      return
    }
    model.tabs = recentTabs.ordered(tabs)
    model.previews = [:]
    // The preview goes toward the window's roomier side, and the column
    // leaves room for it there if the window has it.
    let isPreviewLeading = x > bounds.width / 2
    let half = TabPickerLayout.columnWidth / 2 + TabPickerModel.margin
    let beside =
      TabPickerModel.previewGap + TabPickerLayout.previewSize.width
    var range =
      (half + (isPreviewLeading ? beside : 0))...(bounds.width - half
      - (isPreviewLeading ? 0 : beside))
    if range.isEmpty {
      range = half...max(bounds.width - half, half)
    }
    model.isPreviewLeading = isPreviewLeading
    model.columnMidX = min(max(x, range.lowerBound), range.upperBound)
      .rounded()
    model.revealedCount = 1
    model.isExpanded = true
    leanPoint = nil
    pourX = x
    // The highlight starts on its tab rather than gliding from where it was
    // when the column last closed.
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      highlight(model.tabs[model.activeIndex].tabID)
    }
    animate()
  }

  /// For accessibility, which presses the lip rather than hovering it, and
  /// gets every tab at once.
  private func toggle() {
    if model.isExpanded {
      close()
      return
    }
    open(anchoredAt: model.lipRect.midX)
    guard model.isExpanded else {
      return
    }
    model.revealedCount = model.maxRows
    animate()
  }

  /// Pours the column down to show a tab past `index`, as the pointer or the
  /// highlight reaches it. It doesn't draw back up until it closes.
  private func reveal(through index: Int) {
    let count = min(max(model.revealedCount, index + 2), model.maxRows)
    if count != model.revealedCount {
      model.revealedCount = count
    }
    animate()
  }

  /// The revealed tab across from `point`, the first above the column's
  /// tabs and the last below them; over the preview, the one it shows.
  private func index(at point: CGPoint) -> Int? {
    if let preview = model.previewRect, preview.contains(point) {
      return model.highlightedIndex
    }
    guard model.revealedCount > 0,
      columnRect(rows: model.revealedCount).contains(point)
    else {
      return nil
    }
    return min(
      max(TabPickerLayout.row(atY: point.y), 0), model.revealedCount - 1)
  }

  private func tab(at point: CGPoint) -> FiberTabState? {
    index(at: point).map { model.tabs[$0] }
  }

  /// Highlights a tab, fetching its preview the first time it's highlighted
  /// while the column is open.
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
    let column = columnRect(rows: model.maxRows)
    if (column.minX...column.maxX).contains(point.x) {
      pourX = point.x
      reveal(through: TabPickerLayout.row(atY: point.y))
    }
    // Off every tab, as beside the column, the highlight stays where it was.
    if let tab = tab(at: point) {
      highlight(tab.tabID)
    }
    showCloseButton(near: point)
  }

  /// The close button of the tab the pointer is on, not just across from.
  private func closeButton(near point: CGPoint) -> TabCloseButton? {
    guard columnRect(rows: model.revealedCount).contains(point),
      let index = index(at: point),
      (TabPickerLayout.itemTop(index)...TabPickerLayout.itemTop(index)
        + TabPickerLayout.itemHeight).contains(point.y)
    else {
      return nil
    }
    let button = TabPickerLayout.closeButtonRect(
      index, columnMinX: model.columnMinX)
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
    // The highlight moves off the pointer; a close button would stay behind.
    showCloseButton(near: nil)
    if event.hasPreciseScrollingDeltas {
      trackpadScroll(event)
    } else {
      wheelScroll(event)
    }
  }

  /// As scrolling a list goes: down moves the highlight to older tabs.
  private static func delta(of event: NSEvent) -> CGFloat {
    -event.scrollingDeltaY
  }

  /// Moves the highlight a tab for each step scrolled, and on lift-off
  /// selects the tab it's on.
  private func trackpadScroll(_ event: NSEvent) {
    // The highlight settles at lift-off; it doesn't coast.
    guard event.momentumPhase.isEmpty else {
      return
    }
    switch event.phase {
    case .mayBegin:
      wheelSettleTimer?.invalidate()
    case .began, .changed:
      // A gesture that began over the page picks up from here.
      if event.phase == .began || !isScrolling {
        isScrolling = true
        scrollTravel = 0
      }
      scroll(by: Self.delta(of: event))
    case .ended, .cancelled:
      if isScrolling {
        isScrolling = false
        selectHighlighted()
      }
    case []:
      // A precise device without phases: select once it stops.
      isScrolling = true
      scroll(by: Self.delta(of: event))
      scheduleWheelSettle { [weak self] in
        self?.isScrolling = false
        self?.selectHighlighted()
      }
    default:
      break
    }
  }

  private func scroll(by delta: CGFloat) {
    scrollTravel += delta
    while abs(scrollTravel) >= Metrics.scrollStep {
      let direction: CGFloat = scrollTravel > 0 ? 1 : -1
      scrollTravel -= direction * Metrics.scrollStep
      moveHighlight(by: Int(direction))
    }
  }

  /// A notched wheel moves the highlight a tab per notch, and selects once it
  /// rests.
  private func wheelScroll(_ event: NSEvent) {
    let delta = Self.delta(of: event)
    guard delta != 0 else {
      return
    }
    moveHighlight(by: delta > 0 ? 1 : -1)
    scheduleWheelSettle { [weak self] in self?.selectHighlighted() }
  }

  /// With a tick on the trackpad, pouring the column on ahead of it.
  private func moveHighlight(by offset: Int) {
    let current = model.highlightedIndex ?? model.activeIndex
    let index = min(max(current + offset, 0), model.maxRows - 1)
    guard index != current, model.tabs.indices.contains(index) else {
      return
    }
    highlight(model.tabs[index].tabID)
    reveal(through: index)
    NSHapticFeedbackManager.defaultPerformer.perform(
      .alignment, performanceTime: .now)
  }

  private func selectHighlighted() {
    if let tabID = model.highlightedTabID, tabID != model.activeTabID {
      onSelect(tabID)
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
}

@MainActor
@Observable
final class TabPickerModel {
  /// The column's tabs, as RecentTabs ordered them when it opened.
  var tabs: [FiberTabState] = []
  var activeTabID = 0
  var isExpanded = false
  /// Where the pointer opened the column, as far as the window allows.
  var columnMidX: CGFloat = 0
  /// Whether the preview goes left of the column.
  var isPreviewLeading = false
  /// How many of the tabs the column is pouring down to show.
  var revealedCount = 0
  /// The tab under the pointer, or where scrolling has moved the highlight.
  var highlightedTabID: Int?
  var closeButton: TabCloseButton?
  /// The picker's size, which places the lip.
  var size: CGSize = .zero
  /// The previews fetched since the column opened, by tab ID, nil for a tab
  /// without one.
  var previews: [Int: NSImage?] = [:]
  /// The glass this frame.
  var drop = TabPickerDrop()
  @ObservationIgnored var onToggle: () -> Void = {}
  @ObservationIgnored var onSelect: (Int) -> Void = { _ in }
  @ObservationIgnored var onClose: (Int) -> Void = { _ in }

  /// The lip is a capsule this tall, centered on the window's top edge.
  nonisolated static let lipHeight: CGFloat = 16
  nonisolated static let previewGap: CGFloat = 10
  /// The least room kept beside the column and preview.
  static let margin: CGFloat = 16

  /// A capsule centered on the window's top edge, a third of its width.
  var lipRect: CGRect {
    let width = max(size.width / 3, 120)
    return CGRect(
      x: ((size.width - width) / 2).rounded(), y: -Self.lipHeight / 2,
      width: width, height: Self.lipHeight)
  }

  var columnMinX: CGFloat {
    columnMidX - TabPickerLayout.columnWidth / 2
  }

  /// As many of the tabs as fit down the window.
  var maxRows: Int {
    let room =
      size.height - Self.margin - TabPickerLayout.columnBottom(rows: 1)
    return min(tabs.count, 1 + max(Int(room / TabPickerLayout.step), 0))
  }

  var activeIndex: Int {
    tabs.firstIndex { $0.tabID == activeTabID } ?? 0
  }

  var highlightedIndex: Int? {
    tabs.firstIndex { $0.tabID == highlightedTabID }
  }

  /// How far the glass has poured over tab `index`, from 0 to 1, short of
  /// the column's bottom inset, which reaches past the next tab's top.
  func coverage(ofRow index: Int) -> CGFloat {
    let poured =
      drop.bottom - TabPickerLayout.inset - TabPickerLayout.itemTop(index)
    return min(max(poured / TabPickerLayout.itemHeight, 0), 1)
  }

  /// The highlighted tab's preview: not the active tab's, whose page is
  /// showing.
  var preview: NSImage? {
    guard let tabID = highlightedTabID, tabID != activeTabID else {
      return nil
    }
    return previews[tabID] ?? nil
  }


  /// Beside the highlighted tab, its thumbnail level with it as far down as
  /// the window allows, once the glass has poured over the tab. None in a
  /// window without room for it, rather than over the tabs.
  var previewRect: CGRect? {
    guard isExpanded, preview != nil, let index = highlightedIndex,
      coverage(ofRow: index) > 0.9
    else {
      return nil
    }
    let size = TabPickerLayout.previewSize
    let x =
      isPreviewLeading
      ? columnMinX - Self.previewGap - size.width
      : columnMinX + TabPickerLayout.columnWidth + Self.previewGap
    let lowest = self.size.height - Self.margin - size.height
    guard x >= Self.margin,
      x + size.width <= self.size.width - Self.margin,
      lowest >= TabPickerLayout.rowsTop
    else {
      return nil
    }
    let top = TabPickerLayout.itemTop(index) - TabPickerLayout.previewInset
    let y = min(max(top, TabPickerLayout.rowsTop), lowest)
    return CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
  }
}

/// Where the column puts its tabs, one under another from the window's top
/// edge, shared by hit testing and drawing.
enum TabPickerLayout {
  static let columnWidth: CGFloat = 300
  static let itemHeight: CGFloat = 44
  static let spacing: CGFloat = 2
  /// From the column's sides and bottom to its tabs.
  static let inset: CGFloat = 10
  /// From the window's top edge to the first tab.
  static let rowsTop: CGFloat = 10
  static let cornerRadius = TabListLayout.cornerRadius
  static let rimWidth = TabListLayout.rimWidth
  /// Where the column meets the lip, it curves out into it this sharply.
  static let filletRadius: CGFloat = 18
  static var step: CGFloat { itemHeight + spacing }
  /// A tab's close button is a square this wide at its right end.
  static let closeButtonSize: CGFloat = 24
  static var closeButtonInset: CGFloat { (itemHeight - closeButtonSize) / 2 }
  static let thumbnailSize = CGSize(width: 288, height: 180)
  /// The preview's glass, around the page's thumbnail.
  static let previewInset: CGFloat = 10
  static var previewSize: CGSize {
    CGSize(
      width: thumbnailSize.width + 2 * previewInset,
      height: thumbnailSize.height + 2 * previewInset)
  }

  static func itemTop(_ index: Int) -> CGFloat {
    rowsTop + CGFloat(index) * step
  }

  /// The bottom of the column's glass, showing `rows` tabs.
  static func columnBottom(rows: Int) -> CGFloat {
    itemTop(max(rows, 1)) - spacing + inset
  }

  /// The row across from `y`, negative above the first.
  static func row(atY y: CGFloat) -> Int {
    Int(((y - rowsTop) / step).rounded(.down))
  }

  static func itemFrame(_ index: Int, columnMinX: CGFloat) -> CGRect {
    CGRect(
      x: columnMinX + inset, y: itemTop(index),
      width: columnWidth - 2 * inset, height: itemHeight)
  }

  static func closeButtonRect(_ index: Int, columnMinX: CGFloat) -> CGRect {
    let item = itemFrame(index, columnMinX: columnMinX)
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
