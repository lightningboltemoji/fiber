import AppKit
import SwiftUI

/// Over the page's top-right corner while the active tab has key passthrough
/// (see FiberCommandKeyPassthrough): a keyboard over a button that ends it.
/// Holding Escape ends it too, as a ring around the keyboard fills.
@MainActor
final class KeyPassthroughBubble: NSView {
  /// How long the user holds Escape to end key passthrough.
  static let holdDuration: TimeInterval = 1
  /// How long a full ring takes to drain once the user lets go.
  static let drainDuration: TimeInterval = 0.25

  /// The capsule, in a page of `bounds`: where the first extension window's
  /// bubble goes, below the find bar.
  static func capsuleFrame(in bounds: NSRect) -> NSRect {
    let size = ExtensionBubbleView.size
    return NSRect(
      x: bounds.maxX - ExtensionBubbles.margin - size.width,
      y: bounds.maxY - ExtensionBubbles.firstTop - size.height,
      width: size.width, height: size.height)
  }

  var onEnd: () -> Void = {}
  private(set) var isShown = false

  private let model = KeyPassthroughModel()
  private var holdEnd: DispatchWorkItem?
  private var drainEnd: DispatchWorkItem?

  override init(frame: NSRect) {
    super.init(frame: frame)
    let hostingView = NSHostingView(
      rootView: KeyPassthroughGlass(
        model: model, onEnd: { [weak self] in self?.onEnd() }))
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var mouseDownCanMoveWindow: Bool { false }

  /// In the top-right corner of a page of `bounds`, its superview's.
  func place(in bounds: NSRect) {
    let room = ExtensionBubbleView.shadowRoom
    frame = Self.capsuleFrame(in: bounds).insetBy(dx: -room, dy: -room)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let room = ExtensionBubbleView.shadowRoom
    guard isShown,
      bounds.insetBy(dx: room, dy: room).contains(
        convert(point, from: superview))
    else {
      return nil
    }
    return super.hitTest(point)
  }

  func setShown(_ shown: Bool) {
    guard shown != isShown else {
      return
    }
    isShown = shown
    if shown {
      resetHold()
      isHidden = false
    }
    withAnimation(.spring(duration: 0.35, bounce: shown ? 0.3 : 0).slowMotion) {
      model.isShown = shown
    } completion: { [weak self] in
      guard let self, !self.isShown else {
        return
      }
      self.isHidden = true
      self.resetHold()
    }
  }

  /// Escape went down: the ring fills, ending key passthrough once it's full.
  func holdEscape() {
    guard isShown, !model.hold.isHeld else {
      return
    }
    drainEnd?.cancel()
    let now = Date()
    let level = model.hold.level(at: now)
    model.hold = EscapeHold(level: level, since: now, isHeld: true)
    let end = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.onEnd() }
    }
    holdEnd = end
    DispatchQueue.main.asyncAfter(
      deadline: .now() + (1 - level) * SlowMotion.duration(Self.holdDuration),
      execute: end)
  }

  /// Escape went up, or the window lost the keyboard: the ring drains.
  func releaseEscape() {
    guard model.hold.isHeld else {
      return
    }
    holdEnd?.cancel()
    holdEnd = nil
    let now = Date()
    let level = model.hold.level(at: now)
    model.hold = EscapeHold(level: level, since: now, isHeld: false)
    // Stops the ring's timeline once it's empty.
    let end = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.resetHold() }
    }
    drainEnd = end
    DispatchQueue.main.asyncAfter(
      deadline: .now() + level * SlowMotion.duration(Self.drainDuration),
      execute: end)
  }

  private func resetHold() {
    holdEnd?.cancel()
    holdEnd = nil
    drainEnd?.cancel()
    drainEnd = nil
    model.hold = EscapeHold()
  }
}

/// How full Escape's ring was `since`: filling while it's held, draining
/// after.
struct EscapeHold {
  var level: Double = 0
  var since = Date.distantPast
  var isHeld = false

  @MainActor func level(at date: Date) -> Double {
    let elapsed = date.timeIntervalSince(since)
    if isHeld {
      let fill = SlowMotion.duration(KeyPassthroughBubble.holdDuration)
      return min(1, level + elapsed / fill)
    }
    let drain = SlowMotion.duration(KeyPassthroughBubble.drainDuration)
    return max(0, level - elapsed / drain)
  }
}

@MainActor
@Observable
final class KeyPassthroughModel {
  var isShown = false
  var isCloseHovered = false
  var hold = EscapeHold()
}

/// Draws a KeyPassthroughBubble.
struct KeyPassthroughGlass: View {
  let model: KeyPassthroughModel
  let onEnd: () -> Void

  var body: some View {
    let diameter = ExtensionBubbleView.diameter
    let size = ExtensionBubbleView.size
    ZStack(alignment: .top) {
      PanelShadow(cornerRadius: diameter / 2)
      RimmedGlass(
        cornerRadius: diameter / 2, rimWidth: ExtensionBubbleView.rimWidth)
      keyboard
        .frame(width: diameter, height: diameter)
      closeButton
        .frame(width: diameter, height: diameter)
        .offset(y: size.height - diameter)
    }
    .frame(width: size.width, height: size.height)
    // About the keyboard's center.
    .scaleEffect(
      model.isShown ? 1 : 0.4,
      anchor: UnitPoint(x: 0.5, y: diameter / 2 / size.height))
    .opacity(model.isShown ? 1 : 0)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Key Passthrough")
  }

  private var keyboard: some View {
    ZStack {
      Image(systemName: "keyboard")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.secondary)
      TimelineView(
        .animation(paused: !model.hold.isHeld && model.hold.level == 0)
      ) { context in
        let level = model.hold.level(at: context.date)
        Circle()
          .trim(from: 0, to: level)
          .stroke(
            .primary.opacity(0.6),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .opacity(level > 0 ? 1 : 0)
      }
      // Inside the inner glass.
      .padding(ExtensionBubbleView.rimWidth + 2)
    }
    .contentShape(Circle())
    .help("⌘S, ⌘P and ⌘L go to the page. Hold Esc to stop.")
  }

  private var closeButton: some View {
    Button(action: onEnd) {
      ZStack {
        Circle()
          .fill(.primary.opacity(model.isCloseHovered ? 0.1 : 0))
          .frame(width: 26, height: 26)
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { model.isCloseHovered = $0 }
    .help("Stop Key Passthrough")
    .accessibilityLabel("Stop Key Passthrough")
  }
}
