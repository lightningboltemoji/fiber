import AppKit
import FiberBridge
import SwiftUI

/// The bubbles for the windows extensions open, over a browser window's page
/// (see FiberExtensionWindow). Clicks anywhere else go through to the page.
@MainActor
final class ExtensionBubbles: NSView {
  /// How far bubbles and panels keep from the page's edges.
  static let margin: CGFloat = 16
  /// A new bubble's distance from the top of the page, clear of the toolbar.
  private static let firstTop = margin + Toolbar.height + Toolbar.spacing
  private static let spacing: CGFloat = 12

  /// Called when an open panel with focus closes, for the page to take it.
  var onFocusPage: () -> Void = {}
  /// Called when a bubble goes, and focus may have gone with it.
  var onRemove: () -> Void = {}

  private var bubbles: [ExtensionWindowBubble] = []
  /// The open find bar's frame, which the bubbles move down out of the way of.
  private var keepClear = NSRect.null

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let view = super.hitTest(point)
    return view === self ? nil : view
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    layoutBubbles()
  }

  func add(actions: any FiberExtensionWindowActions) -> ExtensionWindowBubble {
    let bubble = ExtensionWindowBubble(
      actions: actions, container: self, center: freeSpot())
    bubbles.append(bubble)
    // Again now that it's listed, so it keeps clear of the find bar.
    bubble.layout()
    return bubble
  }

  /// Moves the bubbles out of the way of `rect` (in this view), or with
  /// .null, back where they were.
  func setKeepClear(_ rect: NSRect, animated: Bool) {
    guard rect != keepClear else {
      return
    }
    keepClear = rect
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated ? 0.3 : 0
      context.allowsImplicitAnimation = animated
      layoutBubbles()
    }
  }

  fileprivate func layoutBubbles() {
    for bubble in bubbles {
      bubble.layout()
    }
  }

  /// Where `bubble`'s circle goes: where it wants to be, unless that's in the
  /// way of the find bar or a bubble moved for it.
  fileprivate func circleCenter(for bubble: ExtensionWindowBubble) -> NSPoint {
    guard !keepClear.isNull,
      let index = bubbles.firstIndex(where: { $0 === bubble })
    else {
      return bubble.wantedCircleCenter
    }
    return ExtensionBubbleLayout.centers(
      bubbles.map(\.wantedCircleCenter),
      radius: ExtensionBubbleView.diameter / 2, clearOf: keepClear,
      spacing: Self.spacing)[index]
  }

  /// The bubble whose panel has `responder`, if any.
  func bubble(containing responder: NSResponder?) -> ExtensionWindowBubble? {
    guard let view = responder as? NSView else {
      return nil
    }
    return bubbles.first { view.isDescendant(of: $0.panel) }
  }

  fileprivate func willExpand(_ bubble: ExtensionWindowBubble) {
    for other in bubbles where other !== bubble && other.isExpanded {
      other.collapse()
    }
  }

  fileprivate func remove(_ bubble: ExtensionWindowBubble) {
    bubbles.removeAll { $0 === bubble }
    layoutBubbles()
    onRemove()
  }

  /// Down the page's right edge from the top, past the bubbles already there.
  private func freeSpot() -> NSPoint {
    let radius = ExtensionBubbleView.diameter / 2
    var center = NSPoint(
      x: bounds.maxX - Self.margin - radius,
      y: bounds.minY + Self.firstTop + radius)
    let step = ExtensionBubbleView.size.height + Self.spacing
    func isTaken(_ point: NSPoint) -> Bool {
      bubbles.contains {
        $0.circleFrame.insetBy(dx: -Self.spacing, dy: -Self.spacing)
          .contains(point)
      }
    }
    while isTaken(center), center.y + step < bounds.maxY - Self.margin {
      center.y += step
    }
    return center
  }
}

/// Where a panel goes beside its bubble, in flipped coordinates.
enum ExtensionBubbleLayout {
  /// Beside `bubble`, toward the middle of `bounds`: level with its top in the
  /// upper half and its bottom in the lower, within `bounds`, and shrunk to the
  /// room there (down to `minSize`, past which it overlaps the bubble).
  static func panelFrame(
    size: NSSize, beside bubble: NSRect, in bounds: NSRect, gap: CGFloat,
    minSize: NSSize
  ) -> NSRect {
    let toLeft = bubble.midX > bounds.midX
    let room =
      toLeft ? bubble.minX - gap - bounds.minX : bounds.maxX - bubble.maxX - gap
    let width = min(
      max(min(size.width, room), min(size.width, minSize.width)), bounds.width)
    let height = min(size.height, bounds.height)
    let x = toLeft ? bubble.minX - gap - width : bubble.maxX + gap
    let y = bubble.midY < bounds.midY ? bubble.minY : bubble.maxY - height
    return NSRect(
      x: clamp(x, bounds.minX, bounds.maxX - width),
      y: clamp(y, bounds.minY, bounds.maxY - height), width: width,
      height: height)
  }

  static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat)
    -> CGFloat
  {
    max(low, min(value, high))
  }

  /// The circles at `centers`, those in the way of `obstacle` moved down below
  /// it, and those then in the way of a moved one below that, `spacing` apart.
  static func centers(
    _ centers: [NSPoint], radius: CGFloat, clearOf obstacle: NSRect,
    spacing: CGFloat
  ) -> [NSPoint] {
    func circle(_ center: NSPoint) -> NSRect {
      NSRect(
        x: center.x - radius, y: center.y - radius, width: 2 * radius,
        height: 2 * radius)
    }
    var obstacles = [obstacle]
    var result = centers
    for index in centers.indices.sorted(by: { centers[$0].y < centers[$1].y }) {
      var center = centers[index]
      while let hit = obstacles.first(where: {
        $0.intersects(circle(center).insetBy(dx: -spacing, dy: -spacing))
      }) {
        center.y = hit.maxY + spacing + radius
      }
      if center != centers[index] {
        obstacles.append(circle(center))
        result[index] = center
      }
    }
    return result
  }
}

/// Where a bubble sits, as its center's distances from the page's nearest
/// edges, so it keeps to them as the window resizes.
private struct BubbleAnchor {
  var fromRight: Bool
  var fromBottom: Bool
  var x: CGFloat
  var y: CGFloat

  init(center: NSPoint, in bounds: NSRect) {
    fromRight = center.x > bounds.midX
    fromBottom = center.y > bounds.midY
    x = fromRight ? bounds.maxX - center.x : center.x - bounds.minX
    y = fromBottom ? bounds.maxY - center.y : center.y - bounds.minY
  }

  func center(in bounds: NSRect) -> NSPoint {
    NSPoint(
      x: fromRight ? bounds.maxX - x : bounds.minX + x,
      y: fromBottom ? bounds.maxY - y : bounds.minY + y)
  }
}

/// An extension's window: its bubble, and the panel with its page.
@MainActor
final class ExtensionWindowBubble: NSObject, FiberExtensionWindow {
  /// However little the extension asks for, or the page has room for.
  private static let minContentSize = NSSize(width: 240, height: 200)

  let bubbleView = ExtensionBubbleView()
  let panel = ExtensionWindowPanel()
  private(set) var isExpanded = false
  private weak var container: ExtensionBubbles?
  private var actions: (any FiberExtensionWindowActions)?
  private var contentSize = NSSize(width: 400, height: 560)
  private var anchor: BubbleAnchor

  fileprivate init(
    actions: any FiberExtensionWindowActions, container: ExtensionBubbles,
    center: NSPoint
  ) {
    self.actions = actions
    self.container = container
    anchor = BubbleAnchor(center: center, in: container.bounds)
    super.init()
    panel.menuActionTarget = actions
    panel.isHidden = true
    panel.alphaValue = 0
    bubbleView.isHidden = true
    bubbleView.onClick = { [weak self] in self?.toggle() }
    bubbleView.onClose = { [weak self] in
      self?.actions?.extensionWindowShouldClose()
    }
    bubbleView.onDrag = { [weak self] center in self?.move(to: center) }
    // Panels under bubbles, in case one has to cover its own.
    container.addSubview(panel, positioned: .below, relativeTo: nil)
    container.addSubview(bubbleView)
    layout()
  }

  /// The icon's circle, in the container.
  var circleFrame: NSRect {
    bubbleView.circleFrame(in: bubbleView.superview)
  }

  func didBecomeActive() {
    actions?.extensionWindowDidBecomeActive()
  }

  func didResignActive() {
    actions?.extensionWindowDidResignActive()
  }

  // MARK: FiberExtensionWindow

  func setContentsView(_ view: NSView?) {
    panel.setPage(view)
  }

  func setContentSize(_ size: NSSize) {
    contentSize = NSSize(
      width: max(size.width, Self.minContentSize.width),
      height: max(size.height, Self.minContentSize.height))
    layout()
  }

  func setIcon(_ icon: NSImage?) {
    bubbleView.model.icon = icon
  }

  func setTitle(_ title: String) {
    bubbleView.title = title
  }

  func setSite(_ site: String) {
    panel.site = site
    layout()
  }

  var pageFrame: NSRect {
    guard let window = panel.window else {
      return .zero
    }
    return window.convertToScreen(panel.pageFrame(in: nil))
  }

  func expand() {
    show(expanded: true)
  }

  func collapse() {
    show(expanded: false)
  }

  func close() {
    guard let container else {
      return
    }
    actions = nil
    panel.menuActionTarget = nil
    if panelHasFocus {
      container.onFocusPage()
    }
    bubbleView.removeFromSuperview()
    panel.removeFromSuperview()
    self.container = nil
    container.remove(self)
  }

  // MARK: Layout

  /// Where the anchor puts the bubble's circle, within the page.
  fileprivate var wantedCircleCenter: NSPoint {
    guard let container else {
      return .zero
    }
    let bounds = container.bounds.insetBy(
      dx: ExtensionBubbles.margin, dy: ExtensionBubbles.margin)
    let radius = ExtensionBubbleView.diameter / 2
    let wanted = anchor.center(in: container.bounds)
    return NSPoint(
      x: ExtensionBubbleLayout.clamp(
        wanted.x, bounds.minX + radius, bounds.maxX - radius),
      y: ExtensionBubbleLayout.clamp(
        wanted.y, bounds.minY + radius, bounds.maxY - radius))
  }

  /// Puts the bubble where its anchor says, within the page and out of the
  /// find bar's way, and its panel beside it.
  func layout() {
    guard let container else {
      return
    }
    let bounds = container.bounds.insetBy(
      dx: ExtensionBubbles.margin, dy: ExtensionBubbles.margin)
    let radius = ExtensionBubbleView.diameter / 2
    let clear = container.circleCenter(for: self)
    let center = NSPoint(
      x: clear.x,
      y: ExtensionBubbleLayout.clamp(
        clear.y, bounds.minY + radius, bounds.maxY - radius))
    // The capsule grows toward the middle, alongside the panel.
    let growsDown = center.y < bounds.midY
    bubbleView.place(circleCenter: center, growsDown: growsDown)
    panel.frame = ExtensionBubbleLayout.panelFrame(
      size: panel.frameSize(forPage: contentSize),
      beside: bubbleView.circleFrame(in: container), in: bounds,
      gap: Toolbar.spacing,
      minSize: panel.frameSize(forPage: Self.minContentSize))
  }

  private func move(to center: NSPoint) {
    guard let container else {
      return
    }
    anchor = BubbleAnchor(center: center, in: container.bounds)
    // Bubbles below it may have moved out of its way.
    container.layoutBubbles()
  }

  // MARK: Showing

  private var panelHasFocus: Bool {
    guard let responder = panel.window?.firstResponder as? NSView else {
      return false
    }
    return responder.isDescendant(of: panel)
  }

  private func toggle() {
    if isExpanded {
      collapse()
    } else {
      expand()
      actions?.extensionWindowDidExpand()
    }
  }

  private func show(expanded: Bool) {
    guard let container else {
      return
    }
    if bubbleView.isHidden {
      bubbleView.isHidden = false
      bubbleView.appear()
    }
    guard expanded != isExpanded else {
      return
    }
    if expanded {
      container.willExpand(self)
    } else if panelHasFocus {
      container.onFocusPage()
    }
    isExpanded = expanded
    bubbleView.setExpanded(expanded)
    layout()
    if expanded {
      panel.isHidden = false
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = expanded ? 0.18 : 0.14
      panel.animator().alphaValue = expanded ? 1 : 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        // Hidden, so its page counts as hidden, as a minimized window's does.
        if let self, !self.isExpanded {
          self.panel.isHidden = true
        }
      }
    }
  }
}

// MARK: - Panel

/// An extension window's page, in glass, with the page's site above it when
/// it isn't one of the extension's own. Menu actions go to the extension's
/// window while the page has focus.
@MainActor
final class ExtensionWindowPanel: NSView {
  private static let cornerRadius: CGFloat = 22
  private static let rimWidth: CGFloat = 6
  private static let siteHeight: CGFloat = 26

  weak var menuActionTarget: (any FiberExtensionWindowActions)?
  var site: String {
    get { content.site }
    set { content.site = newValue }
  }

  private let shadowView = OutsetShadowView()
  private let glass = RimmedGlassView(rimWidth: ExtensionWindowPanel.rimWidth)
  private let content = PanelContent(
    siteHeight: ExtensionWindowPanel.siteHeight,
    pageCornerRadius: ExtensionWindowPanel.cornerRadius
      - ExtensionWindowPanel.rimWidth)

  override init(frame: NSRect) {
    super.init(frame: frame)
    shadowView.cornerRadius = Self.cornerRadius
    addSubview(shadowView)
    glass.cornerRadius = Self.cornerRadius
    glass.contentView = content
    addSubview(glass)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// The panel's size around a page of `size`.
  func frameSize(forPage size: NSSize) -> NSSize {
    NSSize(
      width: size.width + 2 * Self.rimWidth,
      height: size.height + 2 * Self.rimWidth
        + (site.isEmpty ? 0 : Self.siteHeight))
  }

  func setPage(_ view: NSView?) {
    content.setPage(view)
  }

  func pageFrame(in view: NSView?) -> NSRect {
    content.pageFrame(in: view)
  }

  override var mouseDownCanMoveWindow: Bool { false }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    shadowView.frame = bounds
    glass.frame = bounds
  }

  override func supplementalTarget(forAction action: Selector, sender: Any?)
    -> Any?
  {
    if let menuActionTarget, menuActionTarget.responds(to: action) {
      return menuActionTarget
    }
    return super.supplementalTarget(forAction: action, sender: sender)
  }
}

/// Inside the panel's glass: the site, if shown, over the page.
@MainActor
private final class PanelContent: NSView {
  var site = "" {
    didSet {
      siteLabel.stringValue = site
      siteLabel.isHidden = site.isEmpty
      needsLayout = true
    }
  }

  private let siteHeight: CGFloat
  private let siteLabel = NSTextField(labelWithString: "")
  private let pageView = PageBackground()
  private weak var page: NSView?

  init(siteHeight: CGFloat, pageCornerRadius: CGFloat) {
    self.siteHeight = siteHeight
    super.init(frame: .zero)
    siteLabel.font = .systemFont(ofSize: 11, weight: .medium)
    siteLabel.textColor = .secondaryLabelColor
    siteLabel.alignment = .center
    siteLabel.lineBreakMode = .byTruncatingHead
    siteLabel.isHidden = true
    addSubview(siteLabel)
    pageView.wantsLayer = true
    pageView.layer?.cornerRadius = pageCornerRadius
    pageView.layer?.cornerCurve = .continuous
    pageView.layer?.masksToBounds = true
    addSubview(pageView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  func setPage(_ view: NSView?) {
    if view === page {
      return
    }
    page?.removeFromSuperview()
    page = view
    guard let view else {
      return
    }
    view.frame = pageView.bounds
    view.autoresizingMask = [.width, .height]
    pageView.addSubview(view)
  }

  func pageFrame(in view: NSView?) -> NSRect {
    layoutSubtreeIfNeeded()
    return pageView.convert(pageView.bounds, to: view)
  }

  override func layout() {
    super.layout()
    let top = site.isEmpty ? 0 : siteHeight
    siteLabel.frame = NSRect(
      x: 12, y: (siteHeight - 14) / 2, width: max(bounds.width - 24, 0),
      height: 14)
    pageView.frame = NSRect(
      x: 0, y: top, width: bounds.width, height: max(bounds.height - top, 0))
  }
}

/// Behind the page, which may not draw a background of its own.
@MainActor
private final class PageBackground: NSView {
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
  }
}

// MARK: - Bubble

@MainActor
@Observable
final class ExtensionBubbleModel {
  var icon: NSImage?
  var isExpanded = false
  var growsDown = true
  var isDragging = false
  var isCloseHovered = false
  var isShown = false
}

/// Glass around the extension's icon, which grows into a capsule with a close
/// button while the panel is open. Clicking toggles the panel, and dragging
/// moves the bubble. Its frame leaves room for the shadow around the capsule.
@MainActor
final class ExtensionBubbleView: NSView {
  static let diameter: CGFloat = 44
  /// How far the close button's end of the capsule sits past the icon's.
  static let closeOffset: CGFloat = 32
  /// The capsule's size.
  static let size = NSSize(width: diameter, height: diameter + closeOffset)
  fileprivate static let rimWidth: CGFloat = 5
  /// Around the capsule, for its shadow.
  private static let shadowRoom: CGFloat = 24
  /// How far the pointer moves before a press becomes a drag.
  private static let dragThreshold: CGFloat = 3

  let model = ExtensionBubbleModel()
  var title = "" {
    didSet { toolTip = title }
  }
  var onClick: () -> Void = {}
  var onClose: () -> Void = {}
  /// Where the user dragged the icon's center, in the superview.
  var onDrag: (NSPoint) -> Void = { _ in }

  private let hostingView: NSHostingView<ExtensionBubbleGlass>

  override init(frame: NSRect) {
    hostingView = NSHostingView(rootView: ExtensionBubbleGlass(model: model))
    super.init(frame: frame)
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [
          .mouseEnteredAndExited, .mouseMoved, .activeInActiveApp,
          .inVisibleRect,
        ],
        owner: self))
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  /// Places the view so the icon's circle is centered on `circleCenter`, in
  /// the superview, with the capsule growing down from it or up.
  func place(circleCenter: NSPoint, growsDown: Bool) {
    let size = Self.size
    let radius = Self.diameter / 2
    let capsule = NSRect(
      x: circleCenter.x - radius,
      y: growsDown
        ? circleCenter.y - radius : circleCenter.y + radius - size.height,
      width: size.width, height: size.height)
    frame = capsule.insetBy(dx: -Self.shadowRoom, dy: -Self.shadowRoom)
    if model.growsDown != growsDown {
      withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
        model.growsDown = growsDown
      }
    }
  }

  /// The icon's circle, in `view`'s coordinates.
  func circleFrame(in view: NSView?) -> NSRect {
    convert(circleRect, to: view)
  }

  func setExpanded(_ expanded: Bool) {
    withAnimation(.spring(duration: 0.32, bounce: 0.2)) {
      model.isExpanded = expanded
    }
    if !expanded {
      model.isCloseHovered = false
    }
  }

  func appear() {
    withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
      model.isShown = true
    }
  }

  // MARK: Geometry (flipped)

  private var capsuleRect: NSRect {
    bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom)
  }

  private var circleRect: NSRect {
    let capsule = capsuleRect
    return NSRect(
      x: capsule.minX,
      y: model.growsDown ? capsule.minY : capsule.maxY - Self.diameter,
      width: Self.diameter, height: Self.diameter)
  }

  /// The close button's end of the open capsule, up to halfway between its
  /// center and the icon's.
  private var closeRect: NSRect {
    let capsule = capsuleRect
    let length = Self.size.height - Self.diameter / 2 - Self.closeOffset / 2
    return NSRect(
      x: capsule.minX,
      y: model.growsDown ? capsule.maxY - length : capsule.minY,
      width: Self.diameter, height: length)
  }

  private func isInClose(_ point: NSPoint) -> Bool {
    model.isExpanded && closeRect.contains(point)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden, let superview else {
      return nil
    }
    let local = convert(point, from: superview)
    let area = model.isExpanded ? capsuleRect : circleRect
    return area.contains(local) ? self : nil
  }

  // MARK: Input

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseMoved(with event: NSEvent) {
    updateCloseHover(event)
  }

  override func mouseEntered(with event: NSEvent) {
    updateCloseHover(event)
  }

  override func mouseExited(with event: NSEvent) {
    model.isCloseHovered = false
  }

  private func updateCloseHover(_ event: NSEvent) {
    let hovered = isInClose(convert(event.locationInWindow, from: nil))
    if model.isCloseHovered != hovered {
      model.isCloseHovered = hovered
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard let window, let superview else {
      return
    }
    let start = event.locationInWindow
    let circle = circleFrame(in: superview)
    let startCenter = NSPoint(x: circle.midX, y: circle.midY)
    let pressedClose = isInClose(convert(start, from: nil))
    var isDragging = false
    window.trackEvents(
      matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity,
      mode: .eventTracking
    ) { [weak self] event, stop in
      MainActor.assumeIsolated {
        guard let self, let event else {
          stop.pointee = true
          return
        }
        let point = event.locationInWindow
        // Window coordinates go up; the superview's go down.
        let delta = NSPoint(x: point.x - start.x, y: start.y - point.y)
        switch event.type {
        case .leftMouseDragged:
          if !isDragging, !pressedClose,
            hypot(delta.x, delta.y) > Self.dragThreshold
          {
            isDragging = true
            withAnimation(.spring(duration: 0.2)) {
              self.model.isDragging = true
            }
          }
          if isDragging {
            self.onDrag(
              NSPoint(x: startCenter.x + delta.x, y: startCenter.y + delta.y))
          }
        case .leftMouseUp:
          stop.pointee = true
          if isDragging {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
              self.model.isDragging = false
            }
          } else if pressedClose {
            if self.isInClose(self.convert(point, from: nil)) {
              self.onClose()
            }
          } else {
            self.onClick()
          }
        default:
          break
        }
      }
    }
  }

  // MARK: Accessibility

  override func accessibilityLabel() -> String? {
    title
  }

  override func accessibilityPerformPress() -> Bool {
    onClick()
    return true
  }

  override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
    [
      NSAccessibilityCustomAction(name: "Close") { [weak self] in
        self?.onClose()
        return true
      }
    ]
  }
}

/// Draws an ExtensionBubbleView; the view handles all input.
struct ExtensionBubbleGlass: View {
  let model: ExtensionBubbleModel

  var body: some View {
    let diameter = ExtensionBubbleView.diameter
    let full = ExtensionBubbleView.size
    let height = model.isExpanded ? full.height : diameter
    let alignment: Alignment = model.growsDown ? .top : .bottom
    ZStack(alignment: alignment) {
      PanelShadow(cornerRadius: diameter / 2)
        .frame(width: diameter, height: height)
      RimmedGlass(
        cornerRadius: diameter / 2, rimWidth: ExtensionBubbleView.rimWidth
      )
      .frame(width: diameter, height: height)
      closeButton
        .frame(width: diameter, height: diameter)
        .offset(
          y: model.growsDown ? full.height - diameter : diameter - full.height)
        .opacity(model.isExpanded ? 1 : 0)
      icon
        .frame(width: diameter, height: diameter)
    }
    .frame(width: full.width, height: full.height, alignment: alignment)
    // About the icon's center, which stays put.
    .scaleEffect(
      model.isDragging ? 1.08 : (model.isShown ? 1 : 0.4),
      anchor: UnitPoint(
        x: 0.5,
        y: model.growsDown
          ? diameter / 2 / full.height : 1 - diameter / 2 / full.height))
    .opacity(model.isShown ? 1 : 0)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var icon: some View {
    Group {
      if let image = model.icon {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
      } else {
        Image(systemName: "puzzlepiece.extension")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 22, height: 22)
  }

  private var closeButton: some View {
    ZStack {
      Circle()
        .fill(.primary.opacity(model.isCloseHovered ? 0.1 : 0))
        .frame(width: 26, height: 26)
      Image(systemName: "xmark")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }
  }
}
