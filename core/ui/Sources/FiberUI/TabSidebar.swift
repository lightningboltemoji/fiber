import AppKit
import FiberBridge
import SwiftUI

/// The window's tabs while the toolbar shows: the tab picker's panel, kept
/// open below the toolbar. It fills the column the panel can grow into, but
/// only the panel takes clicks. TabSidebarView draws it.
@MainActor
final class TabSidebar: NSView {
  static let width = TabListLayout.panelWidth

  /// Not called for the tab that's already active.
  var onSelect: (Int) -> Void = { _ in }

  private let model = TabSidebarModel()
  private let hostingView: NSHostingView<TabSidebarView>
  /// Where the fingers have scrolled the list to, before rubber-banding.
  private var dragOffset: CGFloat = 0
  private var pressedTabID: Int?

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
    let activeChanged = activeTabID != model.activeTabID
    model.tabs = tabs
    model.activeTabID = activeTabID
    // Only a new active tab moves the list: a page's title or icon changing
    // leaves it where the user scrolled it.
    if activeChanged {
      revealActiveTab(animated: !isHidden)
    } else {
      setScrollOffset(clamp(model.scrollOffset, to: model.scrollRange))
    }
    // The tabs may have moved under the pointer.
    if model.hoveredTabID != nil, let window {
      hover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
  }

  // MARK: Geometry (flipped: y grows down from the column's top)

  override var isFlipped: Bool { true }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    model.size = newSize
    revealActiveTab(animated: false)
  }

  private func location(of event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
  }

  /// The tab at `point`, where the list is scrolled to now.
  private func tab(at point: CGPoint) -> FiberTabState? {
    guard model.panelRect.contains(point) else {
      return nil
    }
    let offset = point.y + model.scrollOffset - TabListLayout.contentInset
    guard offset >= 0 else {
      return nil
    }
    let row = Int(offset / TabListLayout.rowStep)
    return model.tabs.indices.contains(row) ? model.tabs[row] : nil
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

  // MARK: Pointer

  override func hitTest(_ point: NSPoint) -> NSView? {
    if isHidden {
      return nil
    }
    let point = convert(point, from: superview)
    return model.panelRect.contains(point) ? self : nil
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
    model.hoveredTabID = nil
  }

  override func mouseMoved(with event: NSEvent) {
    hover(at: location(of: event))
  }

  override func mouseEntered(with event: NSEvent) {
    hover(at: location(of: event))
  }

  override func mouseExited(with event: NSEvent) {
    model.hoveredTabID = nil
  }

  override func mouseDown(with event: NSEvent) {
    pressedTabID = tab(at: location(of: event))?.tabID
    if pressedTabID == nil {
      window?.performDrag(with: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    defer { pressedTabID = nil }
    guard let tabID = tab(at: location(of: event))?.tabID,
      tabID == pressedTabID
    else {
      return
    }
    pick(tabID)
  }

  private func hover(at point: CGPoint) {
    let tabID = tab(at: point)?.tabID
    if tabID != model.hoveredTabID {
      model.hoveredTabID = tabID
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
  var tabs: [FiberTabState] = []
  var activeTabID = 0
  var hoveredTabID: Int?
  /// How far the list is scrolled up the panel.
  var scrollOffset: CGFloat = 0
  /// The sidebar's size: as far as the panel can grow.
  var size: CGSize = .zero
  @ObservationIgnored var onSelect: (Int) -> Void = { _ in }

  var panelRect: CGRect {
    CGRect(
      x: 0, y: 0, width: size.width,
      height: min(TabListLayout.panelHeight(rows: tabs.count), size.height))
  }

  var scrollRange: ClosedRange<CGFloat> {
    0...max(TabListLayout.panelHeight(rows: tabs.count) - size.height, 0)
  }
}

/// Draws the tab sidebar; TabSidebar handles all input. The highlight rests
/// on the active tab and glides to the one under the pointer.
struct TabSidebarView: View {
  let model: TabSidebarModel

  var body: some View {
    let panel = model.panelRect
    ZStack(alignment: .top) {
      RimmedGlass(
        cornerRadius: TabListLayout.cornerRadius,
        rimWidth: TabListLayout.rimWidth
      )
      .accessibilityHidden(true)

      TabList(
        tabs: model.tabs, activeTabID: model.activeTabID,
        highlightedTabID: model.hoveredTabID ?? model.activeTabID,
        onSelect: model.onSelect
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
    // Tabs opening and closing grow and shrink it.
    .animation(
      .spring(duration: 0.3, bounce: 0), value: model.tabs.map(\.tabID))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Tabs")
  }
}
