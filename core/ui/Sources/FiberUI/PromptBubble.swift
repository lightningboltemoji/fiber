import AppKit
import FiberBridge
import SwiftUI

/// Something a page asks in a PromptBubble on its tab: Chrome's words, without
/// fields or a checkbox, which a bubble has no room for.
@MainActor
final class BubblePrompt: NSObject, FiberPrompt {
  private let actions: any FiberPromptActions
  private weak var controller: BrowserWindowController?
  private var bubble: PromptBubble?
  private var isDone = false

  init(
    content: FiberPromptContent, tabID: Int, window: NSWindow,
    actions: any FiberPromptActions
  ) {
    self.actions = actions
    controller = BrowserWindowController.controller(for: window)
    super.init()
    let bubble = PromptBubble(content: content) { [weak self] buttonID in
      self?.finish { $0.promptDidPressButton(withID: buttonID) }
    }
    bubble.onRemoved = { [weak self] in
      self?.finish(removing: false) { $0.promptDidDismiss() }
    }
    self.bubble = bubble
    guard let controller else {
      // Nowhere to ask; after returning, since the answer can end the
      // prompt's owner.
      DispatchQueue.main.async {
        self.finish { $0.promptDidDismiss() }
      }
      return
    }
    controller.present(bubble, forTabWithID: tabID)
  }

  var fieldValues: [String] { [] }
  var checkboxChecked: Bool { false }

  func close() {
    finish { $0.promptDidDismiss() }
  }

  /// Takes the bubble down, unless it's already gone, and reports how it
  /// ended, once.
  private func finish(
    removing: Bool = true, _ report: (any FiberPromptActions) -> Void
  ) {
    guard !isDone else {
      return
    }
    isDone = true
    if removing, let bubble {
      controller?.dismiss(bubble)
    }
    report(actions)
  }
}

/// A question in a glass capsule over the page, which stays usable around it.
/// It pops in as a circle around its icon and stretches into the capsule, as
/// a wave like the tab overlay's runs from the icon across its text and
/// buttons. Only its capsule takes clicks.
@MainActor
final class PromptBubble: NSView {
  /// Called if it goes without being answered or dismissed by its owner:
  /// another took its place, or its tab or window closed.
  var onRemoved: (() -> Void)?
  private(set) var isShown = false

  private let model: PromptBubbleModel
  /// Counts showings and hidings, so a step left from an earlier one does
  /// nothing.
  private var generation = 0

  private enum Timing {
    /// How long it shows as a circle before it stretches into the capsule,
    /// and how long after that its confirm buttons can be pressed.
    static let stretchDelay: TimeInterval = 0.6
    static let armDelay: TimeInterval = 0.4
  }

  init(content: FiberPromptContent, onButton: @escaping (Int) -> Void) {
    model = PromptBubbleModel(content: content, onButton: onButton)
    super.init(frame: .zero)
    let hostingView = NSHostingView(rootView: PromptBubbleView(model: model))
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

  override func layout() {
    super.layout()
    if model.pageSize != bounds.size {
      model.pageSize = bounds.size
    }
  }

  override var mouseDownCanMoveWindow: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let size = model.capsuleSize
    let center = model.capsuleCenter
    let capsule = NSRect(
      x: center.x - size.width / 2,
      y: bounds.height - center.y - size.height / 2, width: size.width,
      height: size.height)
    guard isShown, capsule.contains(convert(point, from: superview)) else {
      return nil
    }
    return super.hitTest(point)
  }

  /// Pops in and opens, from wherever it is.
  func show() {
    guard !isShown else {
      return
    }
    isShown = true
    generation += 1
    isHidden = false
    model.isArmed = false
    after(Timing.stretchDelay + Timing.armDelay) { $0.model.isArmed = true }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      withAnimation(.easeOut(duration: 0.2).slowMotion) {
        model.stage = .open
      }
      return
    }
    withAnimation(.spring(duration: 0.35, bounce: 0.4).slowMotion) {
      model.stage = .circle
    }
    after(Timing.stretchDelay) { bubble in
      withAnimation(.spring(duration: 0.55, bounce: 0.2).slowMotion) {
        bubble.model.stage = .open
      }
    }
  }

  /// Shrinks away while its tab isn't active.
  func hide() {
    guard isShown else {
      return
    }
    isShown = false
    generation += 1
    let generation = generation
    withAnimation(.easeIn(duration: 0.15).slowMotion) {
      model.stage = .hidden
    } completion: { [weak self] in
      guard let self, self.generation == generation else {
        return
      }
      self.isHidden = true
    }
  }

  /// Folds back into its icon's circle and shrinks away, then leaves its
  /// superview.
  func leave() {
    isShown = false
    generation += 1
    let wasOpen = model.stage == .open
    if wasOpen {
      withAnimation(.spring(duration: 0.3, bounce: 0).slowMotion) {
        model.stage = .circle
      }
    }
    after(wasOpen ? 0.18 : 0) { bubble in
      withAnimation(.easeIn(duration: 0.15).slowMotion) {
        bubble.model.stage = .hidden
      } completion: {
        bubble.removeFromSuperview()
      }
    }
  }

  /// Runs `step` `delay` from now, unless it has shown or hidden since.
  private func after(
    _ delay: TimeInterval, _ step: @escaping (PromptBubble) -> Void
  ) {
    let generation = generation
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SlowMotion.duration(delay)
    ) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.generation == generation else {
          return
        }
        step(self)
      }
    }
  }
}

@MainActor
@Observable
final class PromptBubbleModel {
  enum Stage {
    case hidden, circle, open
  }

  /// The circle it opens from, which the icon stays in at the capsule's
  /// leading end.
  static let diameter: CGFloat = 56
  static let rimWidth: CGFloat = 5
  /// Kept clear between the capsule and the page's sides.
  static let margin: CGFloat = 24
  /// The capsule is in the middle of a page up to `centeredHeight` tall, and
  /// rises with a taller one, to `raisedPosition` of the way down from
  /// `raisedHeight`.
  static let centeredHeight: CGFloat = 500
  static let raisedHeight: CGFloat = 700
  static let raisedPosition: CGFloat = 1 / 4
  /// How fast the wave spreads, in points a second, its soft edge, and how
  /// much of the text and buttons show past its front.
  static let waveSpeed: CGFloat = 1000
  static let waveEdgeWidth: CGFloat = 160
  static let waveFloorOpacity = 0.3
  /// How long the wave takes to play back as the capsule folds, for each
  /// second it takes as it opens.
  static let waveCloseShare = 0.5

  var stage = Stage.hidden
  /// Its content as laid out in full, which the capsule opens to.
  var contentSize = CGSize.zero
  var pageSize = CGSize.zero
  /// Whether its confirm buttons can be pressed yet.
  var isArmed = false

  let icon: NSImage?
  let eyebrow: String
  let title: String
  /// The message, or the list's items, under the title.
  let lines: [String]
  let buttons: [FiberPromptButton]
  /// The button that's tinted: the last that's default or confirm.
  let prominentButtonID: Int?
  @ObservationIgnored let onButton: (Int) -> Void

  init(content: FiberPromptContent, onButton: @escaping (Int) -> Void) {
    icon = content.icon
    eyebrow = content.eyebrow
    title = content.title
    lines =
      content.message.isEmpty
      ? content.listItems.map(\.text) : [content.message]
    buttons = content.buttons
    prominentButtonID =
      content.buttons.last { $0.role == .default || $0.role == .confirm }?
      .buttonID
    self.onButton = onButton
  }

  var capsuleSize: CGSize {
    let diameter = Self.diameter
    guard stage == .open else {
      return CGSize(width: diameter, height: diameter)
    }
    return CGSize(
      width: max(contentSize.width, diameter),
      height: max(contentSize.height, diameter))
  }

  /// From the page's top-left corner.
  var capsuleCenter: CGPoint {
    let rise = min(
      max(
        (pageSize.height - Self.centeredHeight)
          / (Self.raisedHeight - Self.centeredHeight), 0), 1)
    let position = 0.5 + (Self.raisedPosition - 0.5) * rise
    return CGPoint(x: pageSize.width / 2, y: pageSize.height * position)
  }

  /// How far the far corner of a view `size`, beside the icon, is from the
  /// icon's center.
  static func waveReach(across size: CGSize) -> CGFloat {
    hypot(size.width + diameter / 2, size.height / 2)
  }

  var waveAnimation: Animation {
    let reach = Self.waveReach(
      across: CGSize(
        width: max(contentSize.width - Self.diameter, 0),
        height: contentSize.height))
    let duration = TimeInterval((reach + Self.waveEdgeWidth) / Self.waveSpeed)
    return .linear(
      duration: stage == .open ? duration : Self.waveCloseShare * duration
    ).slowMotion
  }
}

/// Draws a PromptBubble: the capsule, its content laid out whole and cut to
/// it, so the capsule uncovers it as it opens.
struct PromptBubbleView: View {
  private static let textMaxWidth: CGFloat = 300
  private static let textSpacing: CGFloat = 18
  private static let buttonSpacing: CGFloat = 8
  /// Between the last button and the capsule's end.
  private static let endInset: CGFloat = 16
  private static let iconSize: CGFloat = 24

  let model: PromptBubbleModel

  var body: some View {
    let size = model.capsuleSize
    let radius = size.height / 2
    ZStack {
      PanelShadow(cornerRadius: radius)
      RimmedGlass(cornerRadius: radius, rimWidth: PromptBubbleModel.rimWidth)
        .accessibilityHidden(true)
      content
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
          model.contentSize = $0
        }
        .frame(
          width: max(
            model.pageSize.width - 2 * PromptBubbleModel.margin,
            PromptBubbleModel.diameter),
          alignment: .leading
        )
        .frame(width: size.width, height: size.height, alignment: .leading)
        .clipShape(Capsule())
    }
    .frame(width: size.width, height: size.height)
    .scaleEffect(model.stage == .hidden ? 0.4 : 1)
    .opacity(model.stage == .hidden ? 0 : 1)
    .position(model.capsuleCenter)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(model.title)
  }

  private var isOpen: Bool { model.stage == .open }

  private var content: some View {
    HStack(spacing: 0) {
      iconView
        .frame(
          width: PromptBubbleModel.diameter, height: PromptBubbleModel.diameter)
      HStack(spacing: 0) {
        CappedWidth(maxWidth: Self.textMaxWidth) { text }
          .padding(.trailing, Self.textSpacing)
        buttonsRow
          .fixedSize()
      }
      .mask {
        GeometryReader { proxy in
          BubbleWave(progress: isOpen ? 1 : 0, size: proxy.size)
            .animation(model.waveAnimation, value: isOpen)
        }
      }
    }
    .padding(.trailing, Self.endInset)
    .frame(minHeight: PromptBubbleModel.diameter)
  }

  private var iconView: some View {
    Group {
      if let icon = model.icon {
        Image(nsImage: icon)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "questionmark.circle.fill")
          .resizable()
          .scaledToFit()
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: Self.iconSize, height: Self.iconSize)
  }

  private var text: some View {
    VStack(alignment: .leading, spacing: 1) {
      if !model.eyebrow.isEmpty {
        Text(model.eyebrow)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }
      Text(model.title)
        .font(.system(size: 13, weight: .semibold))
      ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
        Text(line)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    }
    .lineLimit(2)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.vertical, 12)
  }

  private var buttonsRow: some View {
    HStack(spacing: Self.buttonSpacing) {
      ForEach(model.buttons, id: \.buttonID) { button in
        bubbleButton(button)
          .disabled(button.role == .confirm && !model.isArmed)
      }
    }
    .controlSize(.large)
  }

  @ViewBuilder
  private func bubbleButton(_ button: FiberPromptButton) -> some View {
    let label = Button(button.title) { model.onButton(button.buttonID) }
    if button.buttonID == model.prominentButtonID {
      label.buttonStyle(.glassProminent)
    } else {
      label.buttonStyle(.glass)
    }
  }
}

/// The mask of the text and buttons beside the icon as the wave spreads
/// across them from the icon's center, as the tab overlay's does across its
/// panel: opaque behind the wave's soft edge, and dimmer past its front.
private struct BubbleWave: View, Animatable {
  /// From the wave not yet started to past the far corner.
  var progress: CGFloat
  /// The masked view's.
  let size: CGSize

  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    let edge = PromptBubbleModel.waveEdgeWidth
    let front =
      progress * (PromptBubbleModel.waveReach(across: size) + edge)
    RadialGradient(
      colors: [
        .black, .black.opacity(PromptBubbleModel.waveFloorOpacity),
      ],
      // The icon's center, before the view's leading edge.
      center: UnitPoint(
        x: size.width > 0 ? -PromptBubbleModel.diameter / 2 / size.width : 0,
        y: 0.5),
      startRadius: max(front - edge, 0), endRadius: max(front, 1))
  }
}

/// Its content as wide as it needs to be, up to `maxWidth`, rather than as
/// wide as it's offered.
private struct CappedWidth: Layout {
  let maxWidth: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    subviews.first?.sizeThatFits(
      ProposedViewSize(
        width: min(proposal.width ?? maxWidth, maxWidth),
        height: proposal.height)) ?? .zero
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
    cache: inout ()
  ) {
    subviews.first?.place(
      at: bounds.origin,
      proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }
}
