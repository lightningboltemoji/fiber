import AppKit
import FiberBridge
import SwiftUI

/// In the window's top-right corner, after a tab opens from the one the user
/// is on: a list like the tab picker's of that tab, which grows to take in
/// the new one, in front of it (so it doesn't pass for the same tab gone
/// somewhere new) or behind it (so it's seen to exist). It goes after a
/// moment, unless the pointer is on it, or when swiped away to the right,
/// like a notification. This view takes the events and keeps the model;
/// OpenedTabNoticeView draws.
@MainActor
final class OpenedTabNotice: NSView {
  /// Called with a tab to switch to, never the active one.
  var onSelect: (Int) -> Void = { _ in }
  var onClose: (Int) -> Void = { _ in }
  /// Right-clicks (or Control-clicks) on a tab, for its menu.
  var onMenu: (Int, NSEvent) -> Void = { _, _ in }

  private enum Metrics {
    /// How long the tab it opened from shows alone before the new one joins.
    static let growDelay: TimeInterval = 0.4
    /// How long it stays once the new tab has joined, and after the pointer
    /// leaves it or a swipe springs back.
    static let holdDuration: TimeInterval = 1.5
    static let lingerDuration: TimeInterval = 0.8
    static let fadeInDuration: TimeInterval = 0.2
    static let fadeOutDuration: TimeInterval = 0.3
    /// How far right a swipe, and a flick's carry past lift-off (in seconds
    /// of its velocity over the last `flickWindow`), takes it to send it off.
    static let swipeDistance: CGFloat = 64
    static let flickProjection: CGFloat = 0.15
    static let flickWindow: TimeInterval = 0.1
    static let swipeOutDuration: TimeInterval = 0.3
    /// How far the pressed pointer moves sideways before it drags rather
    /// than clicks.
    static let dragThreshold: CGFloat = 4
    /// The most tabs opened behind one that it lists, the latest.
    static let maxOpenedTabs = 4
  }

  /// Fingers on the trackpad, or the pressed pointer, moving it sideways.
  private struct Swipe {
    /// How far right, before rubber-banding.
    var offset: CGFloat = 0
    /// Its moves over the last moment, for how fast it was going.
    var samples: [(time: TimeInterval, delta: CGFloat)] = []
  }

  private let model = OpenedTabNoticeModel()
  private let hostingView: NSHostingView<OpenedTabNoticeView>
  /// All the window's tabs, in the tab strip's order, and the active one; it
  /// goes once that changes.
  private var tabs: [FiberTabState] = []
  private var activeTabID = 0
  /// The tab the new ones opened from, and those, in the order they opened.
  private var openerTabID = 0
  private var openedTabIDs: [Int] = []
  private var isShown = false
  private var hasGrown = false
  private var isHovered = false
  private var swipe: Swipe?
  /// Where the pointer was as it showed, in screen coordinates, until it
  /// moves. It wasn't pointed at.
  private var restingPointer: CGPoint?
  private var pressPoint: CGPoint?
  private var pressedTabID: Int?
  private var pressedCloseButtonTabID: Int?
  /// Its growing, or its going.
  private var pendingStep: DispatchWorkItem?
  /// Counts its showings, so that a fade out from one cut short does nothing.
  private var showings = 0

  /// Its frame in `bounds`, for the panel's top-right corner to sit `inset`
  /// from theirs.
  static func frame(in bounds: NSRect, inset: NSSize) -> NSRect {
    let margin = OpenedTabNoticeModel.margin
    let size = NSSize(
      width: TabListLayout.panelWidth + 2 * margin,
      height: TabListLayout.panelHeight(rows: 1 + Metrics.maxOpenedTabs)
        + 2 * margin)
    return NSRect(
      x: bounds.maxX - inset.width - TabListLayout.panelWidth - margin,
      y: bounds.maxY - inset.height + margin - size.height, width: size.width,
      height: size.height)
  }

  override init(frame: NSRect) {
    hostingView = NSHostingView(rootView: OpenedTabNoticeView(model: model))
    super.init(frame: frame)
    wantsLayer = true
    isHidden = true
    alphaValue = 0
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    model.onSelect = { [weak self] tabID in self?.pick(tabID) }
    model.onClose = { [weak self] tabID in self?.onClose(tabID) }
    model.onDismiss = { [weak self] in self?.dismiss() }
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

  /// Shows that `tabID` opened from `openerTabID`, behind it, or in front of
  /// it if `tabID` is the active tab. Another opened behind the same tab
  /// while it shows joins the list; anything else takes its place.
  func show(tabID: Int, openedFrom openerTabID: Int) {
    guard let opener = tabs.first(where: { $0.tabID == openerTabID }),
      tabs.contains(where: { $0.tabID == tabID })
    else {
      return
    }
    if isShown, openerTabID == self.openerTabID, activeTabID == openerTabID {
      openedTabIDs.append(tabID)
      // If it hasn't yet, it takes in all of them when it does.
      if hasGrown {
        grow()
      }
      return
    }
    pendingStep?.cancel()
    showings += 1
    self.openerTabID = openerTabID
    openedTabIDs = [tabID]
    isShown = true
    hasGrown = false
    isHovered = false
    swipe = nil
    pressPoint = nil
    restingPointer = NSEvent.mouseLocation
    model.tabs = [opener]
    model.activeTabID = openerTabID
    model.highlightedTabID = openerTabID
    model.closeButton = nil
    model.swipeOffset = 0
    isHidden = false
    withAnimation(.spring(duration: 0.35, bounce: 0).slowMotion) {
      model.isShown = true
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Metrics.fadeInDuration
      animator().alphaValue = 1
    }
    schedule(after: Metrics.growDelay) { [weak self] in self?.grow() }
  }

  /// The new tabs join the list, and the active row moves to the one opened
  /// in front.
  private func grow() {
    hasGrown = true
    withAnimation(.spring(duration: 0.4, bounce: 0.15).slowMotion) {
      model.tabs = rows
      model.activeTabID = activeTabID
    }
    if isHovered, let point = pointerLocation {
      hover(at: point)
    } else {
      model.highlightedTabID = activeTabID
    }
    if !isHeld {
      schedule(after: Metrics.holdDuration) { [weak self] in self?.dismiss() }
    }
  }

  /// The pointer on it, or a swipe, keeps it.
  private var isHeld: Bool { isHovered || swipe != nil }

  /// Once the new tab has joined, it goes a moment after nothing holds it.
  private func holdDidChange(from wasHeld: Bool) {
    guard hasGrown, isHeld != wasHeld else {
      return
    }
    if isHeld {
      pendingStep?.cancel()
    } else {
      schedule(after: Metrics.lingerDuration) { [weak self] in
        self?.dismiss()
      }
    }
  }

  /// Lifts away as it fades out.
  func dismiss() {
    leave(swipeVelocity: nil)
  }

  /// Lifts away as it fades out, or after a swipe, slides off to the right,
  /// carrying on at the swipe's velocity.
  private func leave(swipeVelocity: CGFloat?) {
    guard isShown else {
      return
    }
    isShown = false
    swipe = nil
    pendingStep?.cancel()
    pendingStep = nil
    pressPoint = nil
    pressedTabID = nil
    pressedCloseButtonTabID = nil
    let showing = showings
    let duration: TimeInterval
    if let swipeVelocity {
      duration = Metrics.swipeOutDuration
      // Past the view's right edge, which is past the window's.
      let distance = bounds.width - model.panelRect.minX
      withAnimation(
        swipeSpring(
          to: distance, velocity: swipeVelocity, duration: duration, bounce: 0)
      ) {
        model.swipeOffset = distance
      }
    } else {
      duration = Metrics.fadeOutDuration
      withAnimation(.easeIn(duration: duration).slowMotion) {
        model.isShown = false
      }
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      if swipeVelocity != nil {
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      }
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isShown, self.showings == showing else {
          return
        }
        self.isHidden = true
        // Swiped off, it hasn't lifted, which it drops back from.
        self.model.isShown = false
      }
    }
  }

  private func schedule(
    after delay: TimeInterval, _ step: @escaping () -> Void
  ) {
    pendingStep?.cancel()
    let item = DispatchWorkItem {
      MainActor.assumeIsolated { step() }
    }
    pendingStep = item
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SlowMotion.duration(delay), execute: item)
  }

  /// The opener, and the latest tabs opened from it, in the tab strip's
  /// order.
  private var rows: [FiberTabState] {
    let tabIDs = Set(
      [openerTabID] + openedTabIDs.suffix(Metrics.maxOpenedTabs))
    return tabs.filter { tabIDs.contains($0.tabID) }
  }

  /// Keeps its rows up to date, and goes once the window switches tabs, or
  /// the opener or all the tabs opened from it have closed.
  func setTabs(_ tabs: [FiberTabState], activeTabID: Int) {
    let didSwitch = activeTabID != self.activeTabID
    self.tabs = tabs
    self.activeTabID = activeTabID
    guard isShown else {
      return
    }
    let tabIDs = Set(tabs.map(\.tabID))
    openedTabIDs.removeAll { !tabIDs.contains($0) }
    guard !didSwitch, tabIDs.contains(openerTabID), !openedTabIDs.isEmpty
    else {
      dismiss()
      return
    }
    let shown = hasGrown ? rows : rows.filter { $0.tabID == openerTabID }
    withAnimation(
      shown.count == model.tabs.count
        ? nil : .spring(duration: 0.3, bounce: 0).slowMotion
    ) {
      model.tabs = shown
    }
  }

  // MARK: Pointer (flipped: y grows down from the top)

  override var isFlipped: Bool { true }

  /// Only the panel, while shown, and of scrolling over it, only a swipe. The
  /// page under it takes the rest.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard isShown,
      model.panelRect.contains(convert(point, from: superview))
    else {
      return nil
    }
    if let event = NSApp.currentEvent, event.type == .scrollWheel {
      return swipe != nil || startsSwipe(event) ? self : nil
    }
    return self
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

  private var pointerLocation: CGPoint? {
    window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
  }

  private func location(of event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
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
    if event.modifierFlags.contains(.control) {
      rightMouseDown(with: event)
      return
    }
    pressPoint = point
    pressedCloseButtonTabID = closeButtonTab(at: point)
    if pressedCloseButtonTabID == nil {
      pressedTabID = tab(at: point)?.tabID
    }
  }

  /// Dragged sideways, it's swiped.
  override func mouseDragged(with event: NSEvent) {
    guard isShown, let pressPoint else {
      return
    }
    let offset = location(of: event).x - pressPoint.x
    if swipe == nil {
      guard abs(offset) >= Metrics.dragThreshold else {
        return
      }
      pressedTabID = nil
      pressedCloseButtonTabID = nil
      beginSwipe()
    }
    moveSwipe(by: offset - (swipe?.offset ?? 0), at: event.timestamp)
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      pressPoint = nil
      pressedTabID = nil
      pressedCloseButtonTabID = nil
    }
    if swipe != nil {
      endSwipe()
      return
    }
    let point = location(of: event)
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
    guard let tab = tab(at: location(of: event)) else {
      return
    }
    onMenu(tab.tabID, event)
  }

  /// The highlight and the close button follow the pointer, once it has
  /// moved, and it stays while the pointer is on it. Nil for the pointer
  /// gone.
  private func hover(at point: CGPoint?) {
    guard isShown, point == nil || restingPointer != NSEvent.mouseLocation
    else {
      return
    }
    restingPointer = nil
    let wasHeld = isHeld
    isHovered = point.map(model.panelRect.contains) ?? false
    holdDidChange(from: wasHeld)
    let highlighted = point.flatMap(tab(at:))?.tabID ?? model.activeTabID
    if highlighted != model.highlightedTabID {
      model.highlightedTabID = highlighted
    }
    let button = point.flatMap(closeButton(near:))
    if button != model.closeButton {
      model.closeButton = button
    }
  }

  private func tab(at point: CGPoint) -> FiberTabState? {
    let panel = model.panelRect
    guard panel.contains(point) else {
      return nil
    }
    let offset = point.y - panel.minY - TabListLayout.contentInset
    guard offset >= 0 else {
      return nil
    }
    let row = Int(offset / TabListLayout.rowStep)
    return model.tabs.indices.contains(row) ? model.tabs[row] : nil
  }

  private func closeButton(near point: CGPoint) -> TabCloseButton? {
    let panel = model.panelRect
    guard panel.contains(point) else {
      return nil
    }
    return TabListLayout.closeButton(
      near: CGPoint(x: point.x - panel.minX, y: point.y - panel.minY),
      in: model.tabs, width: panel.width)
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
    if tabID == activeTabID {
      dismiss()
    } else {
      onSelect(tabID)
    }
  }

  // MARK: Swiping

  /// Two fingers on the trackpad move it with them, and send it off to the
  /// right as a notification goes.
  override func scrollWheel(with event: NSEvent) {
    guard isShown, event.momentumPhase.isEmpty else {
      return
    }
    switch event.phase {
    case .began where startsSwipe(event):
      beginSwipe()
      moveSwipe(by: event.scrollingDeltaX, at: event.timestamp)
    case .changed where swipe != nil:
      moveSwipe(by: event.scrollingDeltaX, at: event.timestamp)
    case .ended, .cancelled:
      endSwipe()
    default:
      break
    }
  }

  /// Fingers starting to move, unless more up or down than sideways.
  private func startsSwipe(_ event: NSEvent) -> Bool {
    event.phase == .began
      && abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
  }

  private func beginSwipe() {
    let wasHeld = isHeld
    swipe = Swipe()
    model.closeButton = nil
    holdDidChange(from: wasHeld)
  }

  /// Freely right, and left with growing resistance.
  private func moveSwipe(by delta: CGFloat, at time: TimeInterval) {
    guard var swipe else {
      return
    }
    swipe.offset += delta
    swipe.samples.append((time, delta))
    swipe.samples.removeAll { time - $0.time > Metrics.flickWindow }
    self.swipe = swipe
    model.swipeOffset = TabListLayout.rubberBand(
      swipe.offset, in: 0...CGFloat.infinity)
  }

  /// Far enough right, or flicked, it goes; otherwise it springs back.
  private func endSwipe() {
    guard let swipe else {
      return
    }
    // Over the last moment up to now, not up to the last move: fingers
    // resting before lift-off send nothing, and shouldn't flick.
    let now = ProcessInfo.processInfo.systemUptime
    let velocity =
      swipe.samples.filter { now - $0.time <= Metrics.flickWindow }
      .reduce(0) { $0 + $1.delta } / Metrics.flickWindow
    if model.swipeOffset + velocity * Metrics.flickProjection
      >= Metrics.swipeDistance
    {
      leave(swipeVelocity: max(velocity, 0))
      return
    }
    let wasHeld = isHeld
    self.swipe = nil
    withAnimation(
      swipeSpring(to: 0, velocity: velocity, duration: 0.35, bounce: 0.2)
    ) {
      model.swipeOffset = 0
    }
    holdDidChange(from: wasHeld)
  }

  /// From where the swipe left it to `target`, carrying on at `velocity`.
  private func swipeSpring(
    to target: CGFloat, velocity: CGFloat, duration: TimeInterval,
    bounce: Double
  ) -> Animation {
    let distance = target - model.swipeOffset
    return .interpolatingSpring(
      duration: duration, bounce: bounce,
      initialVelocity: distance == 0 ? 0 : velocity / distance
    ).slowMotion
  }
}

@MainActor
@Observable
final class OpenedTabNoticeModel {
  /// Around the panel, in the view, for its shadow.
  static let margin: CGFloat = 40
  /// How far the panel drops into place as it shows, and lifts as it goes.
  static let travel: CGFloat = 6

  var tabs: [FiberTabState] = []
  var activeTabID = 0
  var highlightedTabID: Int?
  var closeButton: TabCloseButton?
  var isShown = false
  /// How far right a swipe has moved the panel.
  var swipeOffset: CGFloat = 0
  @ObservationIgnored var onSelect: (Int) -> Void = { _ in }
  @ObservationIgnored var onClose: (Int) -> Void = { _ in }
  @ObservationIgnored var onDismiss: () -> Void = {}

  /// In the view, as tall as its rows.
  var panelRect: CGRect {
    CGRect(
      x: Self.margin, y: Self.margin, width: TabListLayout.panelWidth,
      height: TabListLayout.panelHeight(rows: tabs.count))
  }
}

/// Draws the notice; OpenedTabNotice handles all input. The list is laid out
/// whole and cut to the glass, so the glass uncovers the new row as it grows.
struct OpenedTabNoticeView: View {
  let model: OpenedTabNoticeModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let panel = model.panelRect
    let shape = RoundedRectangle(
      cornerRadius: TabListLayout.cornerRadius, style: .continuous)
    ZStack(alignment: .topLeading) {
      PanelShadow(cornerRadius: TabListLayout.cornerRadius)
      RimmedGlass(
        cornerRadius: TabListLayout.cornerRadius,
        rimWidth: TabListLayout.rimWidth
      )
      .accessibilityHidden(true)
      TabList(
        width: panel.width, tabs: model.tabs, activeTabID: model.activeTabID,
        highlightedTabID: model.highlightedTabID,
        closeButton: model.closeButton, onSelect: model.onSelect,
        onClose: model.onClose
      )
      .frame(width: panel.width, height: panel.height, alignment: .top)
      .clipShape(shape)
    }
    .frame(width: panel.width, height: panel.height)
    .offset(
      x: panel.minX + model.swipeOffset,
      y: panel.minY
        + (model.isShown || reduceMotion ? 0 : -OpenedTabNoticeModel.travel))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Opened Tab")
    .accessibilityAction(named: "Dismiss") { model.onDismiss() }
  }
}
