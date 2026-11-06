import AppKit
import FiberBridge
import SwiftUI

/// The layout of the shelf bar: a capsule with Home's segment and then each
/// shelf's, scrolling across when they don't all fit, and a button after it.
/// Segment frames are from the capsule's top-left corner, unscrolled.
enum ShelfBarLayout {
  static let height = GlassCapsule.height
  static let rimWidth = GlassCapsule.rimWidth
  static let segmentHeight = height - 2 * rimWidth
  static let homeWidth: CGFloat = 40
  static let titleInset: CGFloat = 13
  /// How far each segment's capsule reaches under the next, as the menu bar's
  /// do: titles sit closer together than their capsules would side by side.
  static let segmentOverlap: CGFloat = 8
  /// While renaming, the least a segment's field has to type in.
  static let minFieldWidth: CGFloat = 60
  /// Between the bar's button and what ends the row after it: the downloads,
  /// or the split's spot.
  static let endClearance: CGFloat = 24
  /// How far in from a scrolled edge segments fade out.
  static let fadeWidth: CGFloat = 18
  /// While a row's dragged to it, how far above and below the bar it still
  /// takes the drop.
  static let dropSlop: CGFloat = 12
  /// How far the light under the pointer reaches.
  static let glowRadius: CGFloat = 56
  @MainActor static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
  /// The button's undo symbol and title, and their insets.
  static let undoTitle = "Undo"
  static let undoInset: CGFloat = 14
  static let undoSpacing: CGFloat = 6
  static let undoSymbolWidth: CGFloat = 14

  @MainActor
  static func segmentWidths(names: [String]) -> [CGFloat] {
    [homeWidth] + names.map { textWidth($0) + 2 * titleInset }
  }

  static func contentWidth(segmentWidths widths: [CGFloat]) -> CGFloat {
    widths.reduce(2 * rimWidth, +)
      - CGFloat(max(widths.count - 1, 0)) * segmentOverlap
  }

  static func segmentFrames(widths: [CGFloat]) -> [CGRect] {
    var x = rimWidth
    return widths.map { width in
      defer { x += width - segmentOverlap }
      return CGRect(x: x, y: rimWidth, width: width, height: segmentHeight)
    }
  }

  /// The segment at `x` across the capsule, scrolled `scroll` along. Two that
  /// overlap divide at its middle, halfway between their titles.
  static func segment(at x: CGFloat, scroll: CGFloat, widths: [CGFloat])
    -> Int?
  {
    let frames = segmentFrames(widths: widths)
    let x = x + scroll
    guard let first = frames.first, let last = frames.last,
      (first.minX...last.maxX).contains(x)
    else {
      return nil
    }
    return frames.firstIndex { x < $0.maxX - segmentOverlap / 2 }
      ?? frames.indices.last
  }

  /// A circle, or a capsule while it undoes a deletion.
  @MainActor
  static func buttonWidth(isUndo: Bool) -> CGFloat {
    isUndo
      ? 2 * undoInset + undoSymbolWidth + undoSpacing + textWidth(undoTitle)
      : height
  }

  @MainActor
  private static func textWidth(_ text: String) -> CGFloat {
    (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
  }
}

/// A part of the shelf bar the pointer can be on.
enum ShelfBarPart: Equatable {
  case segment(ShelfSegment)
  /// After the capsule: adds a shelf, or undoes a deletion.
  case button
}

/// A shelf being named, in a field over its segment.
struct ShelfRename: Equatable {
  let shelfID: String
  var name: String
}

/// The tab overlay's shelves, under its panel at the left, opposite the
/// downloads: a capsule with a segment for Home (the window's own tabs) and
/// one for each shelf, and after it a circle that adds a shelf or, for a
/// moment after one's deleted, a capsule that undoes it. It takes its own
/// clicks; it keeps the model, and ShelfBarView draws.
@MainActor
final class ShelfBar: NSView {
  var onSelect: (ShelfSegment) -> Void = { _ in }
  var onAdd: () -> Void = {}
  var onUndo: () -> Void = {}
  var onRename: (_ shelfID: String, _ name: String) -> Void = { _, _ in }
  var onMenu: (FiberShelfState, NSEvent) -> Void = { _, _ in }
  /// Called as it comes to need another width, for the overlay to lay it out
  /// again.
  var onResize: () -> Void = {}
  /// Called once a name's done, for the overlay to have the keyboard back.
  var onRenameEnd: () -> Void = {}

  private let model = ShelfBarModel()
  private let hostingView: ShelfBarHostingView
  private let nameField = ShelfNameField()
  private var pressedPart: ShelfBarPart?

  override init(frame: NSRect) {
    hostingView = ShelfBarHostingView(rootView: ShelfBarView(model: model))
    super.init(frame: frame)
    wantsLayer = true
    hostingView.sizingOptions = []
    // The model's coordinates are the view's, title bar included.
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    nameField.isHidden = true
    addSubview(nameField)
    nameField.onChange = { [weak self] name in
      self?.model.renaming?.name = name
      self?.updateSegmentWidths()
    }
    nameField.onEnd = { [weak self] keep in self?.endRename(keep: keep) }
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

  override var isFlipped: Bool { true }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  var shelves: [FiberShelfState] { model.shelves }
  /// The segment whose list the overlay shows.
  var segment: ShelfSegment { model.segment }
  var segments: [ShelfSegment] { model.segments }
  /// The capsule and the button after it, in the overlay; empty until placed.
  var barFrame: CGRect { model.barFrame }
  var buttonFrame: CGRect { model.buttonFrame }
  /// As wide as its segments.
  var contentWidth: CGFloat {
    ShelfBarLayout.contentWidth(segmentWidths: model.segmentWidths)
  }
  var buttonWidth: CGFloat {
    ShelfBarLayout.buttonWidth(isUndo: model.undoName != nil)
  }
  var isRenaming: Bool { model.renaming != nil }

  func setShelves(_ shelves: [FiberShelfState]) {
    model.shelves = shelves
    if case .shelf(let shelfID) = model.segment,
      !shelves.contains(where: { $0.shelfID == shelfID })
    {
      model.segment = .home
    }
    if let renaming = model.renaming,
      !shelves.contains(where: { $0.shelfID == renaming.shelfID })
    {
      endRename(keep: false)
    }
    updateSegmentWidths()
  }

  /// Highlights `segment`, scrolling the least that shows it whole.
  func select(_ segment: ShelfSegment, animated: Bool) {
    model.segment = segment
    reveal(segment, animated: animated)
  }

  /// The name of a shelf just deleted, which the button undoes for a while,
  /// or nil.
  func setUndoName(_ name: String?) {
    guard name != model.undoName else {
      return
    }
    withAnimation(.spring(duration: 0.35, bounce: 0.2).slowMotion) {
      model.undoName = name
    }
    onResize()
  }

  /// Puts the capsule at `origin`, `width` wide, and the button after it.
  func place(at origin: CGPoint, width: CGFloat) {
    let height = ShelfBarLayout.height
    let bar = CGRect(origin: origin, size: CGSize(width: width, height: height))
    if bar != model.barFrame || buttonWidth != model.buttonFrame.width {
      model.barFrame = bar
      model.buttonFrame = CGRect(
        x: bar.maxX + GlassCapsule.spacing, y: bar.minY, width: buttonWidth,
        height: height)
    }
    let scroll = clamp(model.scroll)
    if scroll != model.scroll {
      model.scroll = scroll
    }
    placeNameField()
  }

  /// The segment a row dropped at `point` would go to, with a little to spare
  /// above and below the capsule.
  func segment(forDropAt point: CGPoint) -> ShelfSegment? {
    let bar = model.barFrame
    guard bar.insetBy(dx: 0, dy: -ShelfBarLayout.dropSlop).contains(point)
    else {
      return nil
    }
    return ShelfBarLayout.segment(
      at: point.x - bar.minX, scroll: model.scroll,
      widths: model.segmentWidths
    ).map { model.segments[$0] }
  }

  /// Lights up the segment a dragged row would drop on.
  func setDropTarget(_ segment: ShelfSegment?) {
    if segment != model.dropTarget {
      model.dropTarget = segment
    }
  }

  /// For the bar going away with the pointer on it, which no event reports.
  func endHover() {
    hover(at: nil)
  }

  /// Puts a field over the shelf's segment, with its name selected.
  func beginRename(_ shelfID: String) {
    guard
      let shelf = model.shelves.first(where: { $0.shelfID == shelfID })
    else {
      return
    }
    reveal(.shelf(shelfID), animated: true)
    model.renaming = ShelfRename(shelfID: shelfID, name: shelf.name)
    nameField.stringValue = shelf.name
    nameField.isHidden = false
    updateSegmentWidths()
    placeNameField()
    window?.makeFirstResponder(nameField)
    nameField.currentEditor()?.selectAll(nil)
  }

  /// Keeps the name typed, if `keep` and it's not empty, or the one it had.
  func endRename(keep: Bool) {
    guard let renaming = model.renaming else {
      return
    }
    model.renaming = nil
    nameField.isHidden = true
    let name = renaming.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let shelf = model.shelves.first { $0.shelfID == renaming.shelfID }
    if keep, !name.isEmpty, name != shelf?.name {
      onRename(renaming.shelfID, name)
    }
    updateSegmentWidths()
    onRenameEnd()
  }

  // MARK: Layout

  private func updateSegmentWidths() {
    var names = model.shelves.map(\.name)
    if let renaming = model.renaming,
      let index = model.shelves.firstIndex(where: {
        $0.shelfID == renaming.shelfID
      })
    {
      names[index] = renaming.name
    }
    var widths = ShelfBarLayout.segmentWidths(names: names)
    if let index = model.renamingSegmentIndex {
      widths[index] = max(widths[index], ShelfBarLayout.minFieldWidth)
    }
    if widths != model.segmentWidths {
      model.segmentWidths = widths
      onResize()
    }
  }

  private func reveal(_ segment: ShelfSegment, animated: Bool) {
    guard let index = model.segments.firstIndex(of: segment),
      model.segmentWidths.indices.contains(index)
    else {
      return
    }
    let frame = ShelfBarLayout.segmentFrames(widths: model.segmentWidths)[
      index]
    let width = model.barFrame.width
    let edge = ShelfBarLayout.rimWidth + ShelfBarLayout.fadeWidth
    let scroll = clamp(
      min(max(model.scroll, frame.maxX + edge - width), frame.minX - edge))
    withAnimation(animated ? .spring(duration: 0.3, bounce: 0).slowMotion : nil)
    {
      model.scroll = scroll
    }
    placeNameField()
  }

  private func clamp(_ scroll: CGFloat) -> CGFloat {
    min(max(scroll, 0), model.scrollRange.upperBound)
  }

  private func placeNameField() {
    guard let index = model.renamingSegmentIndex,
      model.segmentWidths.indices.contains(index)
    else {
      return
    }
    let segment = ShelfBarLayout.segmentFrames(widths: model.segmentWidths)[
      index]
    let height = nameField.fittingSize.height
    let bar = model.barFrame
    nameField.frame = CGRect(
      x: bar.minX + segment.minX - model.scroll + 8,
      y: bar.minY + segment.midY - height / 2,
      width: segment.width - 16, height: height)
  }

  // MARK: Pointer

  /// Its glass takes the pointer, the field over a segment being named
  /// included; nothing else does.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let point = convert(point, from: superview)
    guard !isHidden, part(at: point) != nil else {
      return nil
    }
    if !nameField.isHidden, nameField.frame.contains(point) {
      return nameField.hitTest(convert(point, to: nameField.superview))
    }
    return self
  }

  private func part(at point: CGPoint) -> ShelfBarPart? {
    let button = model.buttonFrame
    let isOnButton =
      model.undoName != nil
      ? button.contains(point)
      : hypot(point.x - button.midX, point.y - button.midY) <= button.height / 2
    if isOnButton {
      return .button
    }
    let bar = model.barFrame
    guard bar.contains(point) else {
      return nil
    }
    return ShelfBarLayout.segment(
      at: point.x - bar.minX, scroll: model.scroll,
      widths: model.segmentWidths
    ).map { .segment(model.segments[$0]) }
  }

  private func location(of event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
  }

  override func mouseDown(with event: NSEvent) {
    endRename(keep: true)
    if event.modifierFlags.contains(.control) {
      showMenu(for: event)
      return
    }
    pressedPart = part(at: location(of: event))
  }

  override func mouseUp(with event: NSEvent) {
    defer { pressedPart = nil }
    guard let pressed = pressedPart, part(at: location(of: event)) == pressed
    else {
      return
    }
    switch pressed {
    case .button:
      if model.undoName != nil {
        onUndo()
      } else {
        onAdd()
      }
    case .segment(.shelf(let shelfID)) where event.clickCount == 2:
      beginRename(shelfID)
    case .segment(let segment):
      onSelect(segment)
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    endRename(keep: true)
    showMenu(for: event)
  }

  override func otherMouseDown(with event: NSEvent) {}

  private func showMenu(for event: NSEvent) {
    guard case .segment(.shelf(let shelfID))? = part(at: location(of: event)),
      let shelf = model.shelves.first(where: { $0.shelfID == shelfID })
    else {
      return
    }
    onMenu(shelf, event)
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

  private func hover(at point: CGPoint?) {
    let wasGlowing = model.isGlowing
    let part = point.flatMap(part(at:))
    if part != model.hoveredPart {
      model.hoveredPart = part
    }
    if case .segment? = part, let point {
      model.pointerX = point.x - model.barFrame.minX
    }
    if model.isGlowing, !wasGlowing {
      model.glowCount += 1
    }
  }

  /// Scrolls the segments across, with either axis.
  override func scrollWheel(with event: NSEvent) {
    let delta =
      abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
      ? -event.scrollingDeltaX : -event.scrollingDeltaY
    let step = event.hasPreciseScrollingDeltas ? delta : delta * 20
    model.scroll = clamp(model.scroll + step)
    placeNameField()
    hover(at: location(of: event))
  }
}

/// Takes the first click in an inactive window, as the rest of the overlay
/// does.
private final class ShelfBarHostingView: NSHostingView<ShelfBarView> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }
}

@MainActor
@Observable
final class ShelfBarModel {
  var shelves: [FiberShelfState] = []
  var segment: ShelfSegment = .home
  /// Home's, then each shelf's (see ShelfBarLayout).
  var segmentWidths: [CGFloat] = []
  /// In the overlay; empty until placed.
  var barFrame: CGRect = .zero
  var buttonFrame: CGRect = .zero
  /// How far the segments are scrolled across the capsule.
  var scroll: CGFloat = 0
  var hoveredPart: ShelfBarPart?
  /// Across the capsule, where the pointer was last on a segment.
  var pointerX: CGFloat = 0
  /// How many times the light under the pointer has come on.
  var glowCount = 0
  var dropTarget: ShelfSegment?
  var renaming: ShelfRename?
  var undoName: String?

  var segments: [ShelfSegment] {
    [.home] + shelves.map { .shelf($0.shelfID) }
  }

  var renamingSegmentIndex: Int? {
    renaming.flatMap { segments.firstIndex(of: .shelf($0.shelfID)) }
  }

  /// Whether the pointer's on a segment the capsule isn't, with no row being
  /// dragged.
  var isGlowing: Bool {
    guard case .segment(let hovered)? = hoveredPart else {
      return false
    }
    return hovered != segment && dropTarget == nil
  }

  var scrollRange: ClosedRange<CGFloat> {
    0...max(
      ShelfBarLayout.contentWidth(segmentWidths: segmentWidths)
        - barFrame.width, 0)
  }
}

/// Draws the shelf bar where its model has it; ShelfBar takes its input. Its
/// one capsule glides from the selected segment to one a row is dragged onto;
/// the pointer's a light in the glass, since two capsules would overlap.
struct ShelfBarView: View {
  let model: ShelfBarModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let bar = model.barFrame
    let button = model.buttonFrame
    let rim = ShelfBarLayout.rimWidth
    let frames = ShelfBarLayout.segmentFrames(widths: model.segmentWidths)
    let segments = model.segments
    ZStack(alignment: .topLeading) {
      RimmedGlass(cornerRadius: bar.height / 2, rimWidth: rim)
        .frame(width: bar.width, height: bar.height)
        .offset(x: bar.minX, y: bar.minY)
        .accessibilityHidden(true)

      pointerGlow(bar: bar)

      ZStack(alignment: .topLeading) {
        highlight(frames)
        if let index = model.renamingSegmentIndex, frames.indices.contains(index)
        {
          Capsule()
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .frame(width: frames[index].width, height: frames[index].height)
            .offset(x: frames[index].minX, y: frames[index].minY)
        }
        ForEach(Array(zip(segments, frames)), id: \.0) { segment, frame in
          label(of: segment)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(
              segment == model.segment ? [.isButton, .isSelected] : .isButton)
        }
      }
      .offset(x: -model.scroll)
      .frame(width: bar.width, height: bar.height, alignment: .topLeading)
      .mask { edgeFade(width: bar.width) }
      .offset(x: bar.minX, y: bar.minY)
      .animation(
        .spring(duration: 0.25, bounce: 0).slowMotion, value: model.dropTarget)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Shelves")

      ShelfButton(
        isUndo: model.undoName != nil, isHovered: model.hoveredPart == .button
      )
      .frame(width: button.width, height: button.height)
      .offset(x: button.minX, y: button.minY)
      .accessibilityElement()
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(
        model.undoName.map { "Undo Delete \($0)" } ?? "New Shelf")
    }
    .animation(
      TabOverlayMotion.layoutAnimation.slowMotion, value: model.segmentWidths)
    .animation(
      TabOverlayMotion.layoutAnimation.slowMotion, value: model.barFrame)
    .animation(.easeOut(duration: 0.15).slowMotion, value: model.hoveredPart)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// The capsule, on the segment a dragged row would drop on, or else the
  /// selected one.
  @ViewBuilder private func highlight(_ frames: [CGRect]) -> some View {
    let target = model.dropTarget ?? model.segment
    if let index = model.segments.firstIndex(of: target),
      frames.indices.contains(index)
    {
      Capsule()
        .fill(
          model.dropTarget == nil
            ? Color.primary.opacity(0.13) : Color.accentColor.opacity(0.55)
        )
        .frame(width: frames[index].width, height: frames[index].height)
        .offset(x: frames[index].minX, y: frames[index].minY)
        .animation(
          .spring(duration: 0.3, bounce: 0.15).slowMotion, value: index)
    }
  }

  /// A soft light under the pointer, in the inner glass. Each time it comes on
  /// it's a new view, so it rises where the pointer came in, and the last one
  /// fades where it left rather than sliding across.
  private func pointerGlow(bar: CGRect) -> some View {
    let rim = ShelfBarLayout.rimWidth
    let radius = ShelfBarLayout.glowRadius
    let height = bar.height - 2 * rim
    // White has less to stand out from on light glass.
    let strength = colorScheme == .dark ? 0.17 : 0.6
    return ZStack(alignment: .topLeading) {
      if model.isGlowing {
        RadialGradient(
          colors: [.white.opacity(strength), .white.opacity(0)],
          center: .center, startRadius: 0, endRadius: radius
        )
        .frame(width: 2 * radius, height: 2 * radius)
        .offset(x: model.pointerX - rim - radius, y: height / 2 - radius)
        .animation(.easeOut(duration: 0.08).slowMotion, value: model.pointerX)
        .id(model.glowCount)
        .transition(
          .asymmetric(
            insertion: .opacity.animation(.easeInOut(duration: 0.4).slowMotion),
            removal: .opacity.animation(.easeOut(duration: 0.25).slowMotion)))
      }
    }
    .frame(
      width: max(bar.width - 2 * rim, 0), height: height, alignment: .topLeading
    )
    .clipShape(Capsule())
    .offset(x: bar.minX + rim, y: bar.minY + rim)
    .accessibilityHidden(true)
  }

  @ViewBuilder private func label(of segment: ShelfSegment) -> some View {
    let isBright =
      segment == model.segment || model.hoveredPart == .segment(segment)
    switch segment {
    case .home:
      Image(systemName: "house.fill")
        .font(.system(size: 13))
        .foregroundStyle(isBright ? .primary : .secondary)
        .accessibilityLabel("Home")
    case .shelf(let shelfID):
      let name = model.shelves.first { $0.shelfID == shelfID }?.name ?? ""
      Text(name)
        .font(Font(ShelfBarLayout.font as CTFont))
        .foregroundStyle(isBright ? .primary : .secondary)
        .lineLimit(1)
        .fixedSize()
        // The field over it shows the name being typed.
        .opacity(model.renaming?.shelfID == shelfID ? 0 : 1)
    }
  }

  /// Segments scrolled past an edge fade into it.
  private func edgeFade(width: CGFloat) -> some View {
    let range = model.scrollRange
    let rim = ShelfBarLayout.rimWidth
    return HStack(spacing: 0) {
      Color.clear.frame(width: rim)
      LinearGradient(
        colors: [model.scroll > range.lowerBound ? .clear : .black, .black],
        startPoint: .leading, endPoint: .trailing
      )
      .frame(width: ShelfBarLayout.fadeWidth)
      Color.black
      LinearGradient(
        colors: [.black, model.scroll < range.upperBound ? .clear : .black],
        startPoint: .leading, endPoint: .trailing
      )
      .frame(width: ShelfBarLayout.fadeWidth)
      Color.clear.frame(width: rim)
    }
    .frame(width: width)
  }
}

/// The circle after the shelf bar that adds a shelf, which for a moment after
/// one's deleted widens into a capsule that undoes it.
private struct ShelfButton: View {
  let isUndo: Bool
  let isHovered: Bool

  var body: some View {
    let rim = ShelfBarLayout.rimWidth
    ZStack {
      RimmedGlass(
        cornerRadius: ShelfBarLayout.height / 2, rimWidth: rim)
      Capsule()
        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
        .padding(rim)
      if isUndo {
        HStack(spacing: ShelfBarLayout.undoSpacing) {
          Image(systemName: "arrow.uturn.backward")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: ShelfBarLayout.undoSymbolWidth)
          Text(ShelfBarLayout.undoTitle)
            .font(Font(ShelfBarLayout.font as CTFont))
            .fixedSize()
        }
        .foregroundStyle(.primary)
        .transition(.opacity)
      } else {
        Image(systemName: "plus")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
          .transition(.opacity)
      }
    }
  }
}

/// A field over a shelf's segment, for naming it. Return or a click off it
/// keeps the name; Escape keeps the one it had.
final class ShelfNameField: NSTextField, NSTextFieldDelegate {
  var onChange: (String) -> Void = { _ in }
  var onEnd: (_ keep: Bool) -> Void = { _ in }

  init() {
    super.init(frame: .zero)
    isBordered = false
    drawsBackground = false
    focusRingType = .none
    font = ShelfBarLayout.font
    alignment = .center
    // Without a content type, AppKit's AutoFill guesses one, and offers
    // one-time codes in a list that flashes up under the field.
    contentType = .URL
    cell?.isScrollable = true
    cell?.lineBreakMode = .byClipping
    delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func controlTextDidChange(_ notification: Notification) {
    onChange(stringValue)
  }

  func control(
    _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
  ) -> Bool {
    switch selector {
    case #selector(insertNewline(_:)):
      onEnd(true)
    case #selector(cancelOperation(_:)):
      onEnd(false)
    default:
      return false
    }
    return true
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    onEnd(true)
  }
}
