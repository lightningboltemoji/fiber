import AppKit
import SwiftUI

/// The hovered link's URL, or failing that the page's load status, in a glass
/// capsule in the page's bottom-left corner. A URL too long for the capsule
/// shows whole once the pointer rests on its link. The capsule keeps clear of
/// the pointer, going to the bottom-right corner when it comes near.
@MainActor
final class StatusBubble: NSView {
  fileprivate enum Metrics {
    static let height: CGFloat = 28
    static let rimWidth: CGFloat = 3
    /// From the page's edges.
    static let inset: CGFloat = 10
    /// From the capsule's ends to the text.
    static let textInset: CGFloat = 12
    @MainActor static let font = NSFont.systemFont(ofSize: 12)
    /// How near the pointer comes before the capsule moves out of its way.
    static let pointerClearance: CGFloat = 20
    /// How long a link is pointed at before the capsule shows, so that links
    /// the pointer only crosses don't flash it.
    static let showDelay: TimeInterval = 0.08
    /// How long it stays with nothing to show, for the pointer to reach the
    /// next link.
    static let hideDelay: TimeInterval = 0.25
    /// How long the pointer rests on a link before a URL too long for the
    /// capsule shows whole (Chrome's StatusBubble::kExpandHoverDelayMS).
    static let expandDelay: TimeInterval = 1.6
  }

  private let model = StatusBubbleModel()
  /// Made the first time it shows.
  private var hostingView: NSHostingView<StatusBubbleView>?
  /// What it shows, or is about to; empty while it's going.
  private var text = ""
  /// In the view, while the pointer's over the page.
  private var pointer: NSPoint?
  /// Whether a URL too long for the capsule shows whole. It does until the
  /// capsule has gone.
  private var isExpanded = false
  /// New text while it fades out shows at once.
  private var isFadingOut = false
  /// Counts its showings, so that a fade out cut short does nothing.
  private var showings = 0
  /// Its showing or hiding, after a delay.
  private var pendingChange: DispatchWorkItem?
  private var pendingExpansion: DispatchWorkItem?

  override init(frame: NSRect) {
    super.init(frame: frame)
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    hostingView?.frame = hostingFrame
    place(animation: nil)
  }

  /// Along the page's bottom edge.
  private var hostingFrame: NSRect {
    NSRect(
      x: 0, y: 0, width: bounds.width,
      height: Metrics.height + 2 * Metrics.inset)
  }

  /// Shows `text`, after a moment unless it's showing. Empty hides it after a
  /// moment.
  func setText(_ text: String) {
    guard text != self.text else {
      return
    }
    self.text = text
    pendingChange?.cancel()
    pendingChange = nil
    if text.isEmpty {
      pendingExpansion?.cancel()
      pendingExpansion = nil
      if model.isShown {
        pendingChange = after(Metrics.hideDelay) {
          $0.fadeOut(duration: 0.2)
        }
      }
      return
    }
    scheduleExpansion()
    if model.isShown {
      place(animation: .spring(duration: 0.3, bounce: 0))
    } else if isFadingOut {
      show()
    } else {
      pendingChange = after(Metrics.showDelay) { $0.show() }
    }
  }

  /// Hides it at once, as the page navigates or another tab's shows.
  func hide() {
    text = ""
    fadeOut(duration: 0.1)
  }

  /// Where the pointer is, in the view, or nil while it's off the page.
  func setPointer(_ point: NSPoint?) {
    pointer = point
    if model.isShown {
      place(animation: .easeInOut(duration: 0.15))
    }
  }

  private func show() {
    showings += 1
    isFadingOut = false
    isHidden = false
    place(animation: nil)
    if hostingView == nil {
      let hostingView = NSHostingView(rootView: StatusBubbleView(model: model))
      hostingView.sizingOptions = []
      hostingView.safeAreaRegions = []
      hostingView.frame = hostingFrame
      addSubview(hostingView)
      // Drawn hidden first, to fade in from.
      hostingView.layoutSubtreeIfNeeded()
      self.hostingView = hostingView
    }
    withAnimation(.easeOut(duration: 0.15).slowMotion) {
      model.isShown = true
    }
  }

  private func fadeOut(duration: TimeInterval) {
    pendingChange?.cancel()
    pendingChange = nil
    pendingExpansion?.cancel()
    pendingExpansion = nil
    guard model.isShown else {
      return
    }
    isFadingOut = true
    let showing = showings
    withAnimation(.easeIn(duration: duration).slowMotion) {
      model.isShown = false
    } completion: { [weak self] in
      guard let self, self.showings == showing, !self.model.isShown else {
        return
      }
      self.isFadingOut = false
      self.isHidden = true
      self.isExpanded = false
      self.model.corner = .bottomLeft
    }
  }

  private func scheduleExpansion() {
    pendingExpansion?.cancel()
    pendingExpansion = nil
    guard !isExpanded, Self.width(of: text) > standardWidth else {
      return
    }
    pendingExpansion = after(Metrics.expandDelay) {
      $0.isExpanded = true
      $0.place(animation: .spring(duration: 0.4, bounce: 0))
    }
  }

  /// Sizes the capsule to the text, as wide as it may be, and puts it in the
  /// corner that's clear of the pointer.
  private func place(animation: Animation?) {
    guard !text.isEmpty else {
      return
    }
    var width = min(
      Self.width(of: text), isExpanded ? maxWidth : standardWidth)
    var corner = model.corner
    if let pointer,
      pointer.y < Metrics.inset + Metrics.height + Metrics.pointerClearance,
      !isClear(of: pointer, in: corner, width: width)
    {
      if isClear(of: pointer, in: corner.opposite, width: width) {
        corner = corner.opposite
      } else {
        // Near it in either corner: in the one with more room, cut to fit.
        let clearance = Metrics.inset + Metrics.pointerClearance
        let leftRoom = pointer.x - clearance
        let rightRoom = bounds.width - clearance - pointer.x
        corner = leftRoom >= rightRoom ? .bottomLeft : .bottomRight
        width = max(leftRoom, rightRoom, Metrics.height)
      }
    }
    withAnimation(animation?.slowMotion) {
      if model.text != text {
        model.text = text
      }
      if model.width != width {
        model.width = width
      }
      if model.corner != corner {
        model.corner = corner
      }
    }
  }

  private func isClear(
    of pointer: NSPoint, in corner: StatusBubbleModel.Corner, width: CGFloat
  ) -> Bool {
    let minX =
      corner == .bottomLeft
      ? Metrics.inset : bounds.width - Metrics.inset - width
    return pointer.x < minX - Metrics.pointerClearance
      || pointer.x > minX + width + Metrics.pointerClearance
  }

  /// The widest it gets until the pointer rests on a link.
  private var standardWidth: CGFloat {
    min(bounds.width / 2, maxWidth)
  }

  private var maxWidth: CGFloat {
    max(bounds.width - 2 * Metrics.inset, Metrics.height)
  }

  /// The capsule's, to fit `text`.
  private static func width(of text: String) -> CGFloat {
    let size = (text as NSString).size(withAttributes: [.font: Metrics.font])
    // A point spare, for SwiftUI not to truncate text that just fits.
    return size.width.rounded(.up) + 1 + 2 * Metrics.textInset
  }

  private func after(
    _ delay: TimeInterval, _ body: @escaping @MainActor (StatusBubble) -> Void
  ) -> DispatchWorkItem {
    let item = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self else {
          return
        }
        body(self)
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    return item
  }
}

@MainActor
@Observable
private final class StatusBubbleModel {
  enum Corner {
    case bottomLeft, bottomRight

    var opposite: Corner {
      self == .bottomLeft ? .bottomRight : .bottomLeft
    }
  }

  var text = ""
  var width: CGFloat = 0
  var corner = Corner.bottomLeft
  var isShown = false
}

/// Draws a StatusBubble: a capsule in each bottom corner, which shows in the
/// model's corner, so that moving corners fades it out of one and into the
/// other.
private struct StatusBubbleView: View {
  private typealias Metrics = StatusBubble.Metrics

  let model: StatusBubbleModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      capsule(in: .bottomLeft)
      capsule(in: .bottomRight)
    }
    .padding(Metrics.inset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
  }

  private func capsule(in corner: StatusBubbleModel.Corner) -> some View {
    let isShown = model.isShown && model.corner == corner
    let alignment: Alignment = corner == .bottomLeft ? .leading : .trailing
    return ZStack {
      RimmedGlass(
        cornerRadius: Metrics.height / 2, rimWidth: Metrics.rimWidth)
      Text(verbatim: model.text)
        .font(Font(Metrics.font as CTFont))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, Metrics.textInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        // New text is laid out at its new width at once, which the glass
        // uncovers as it grows.
        .clipShape(Capsule())
    }
    .frame(width: model.width, height: Metrics.height)
    .scaleEffect(
      isShown || reduceMotion ? 1 : 0.9,
      anchor: corner == .bottomLeft ? .leading : .trailing)
    .opacity(isShown ? 1 : 0)
    .frame(maxWidth: .infinity, alignment: alignment)
    .accessibilityHidden(!isShown)
  }
}
