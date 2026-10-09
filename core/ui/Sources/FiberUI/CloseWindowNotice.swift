import AppKit
import SwiftUI

/// In OpenedTabNotice's place and glass, after the user tries to close the
/// window's last tab, a New Tab page, which stays: that Command-W again closes
/// the window. Clicks go through it, and it goes after a moment.
@MainActor
final class CloseWindowNotice: NSView {
  private enum Metrics {
    /// How long it stays after the last try.
    static let holdDuration: TimeInterval = 2.5
    static let fadeInDuration: TimeInterval = 0.2
    static let fadeOutDuration: TimeInterval = 0.3
  }

  private(set) var isShown = false
  private let model = CloseWindowNoticeModel()
  private var pendingDismissal: DispatchWorkItem?
  /// Counts its showings, so that a fade out from one cut short does nothing.
  private var showings = 0

  /// Its frame, for the panel's top-right corner to sit `inset` from that of
  /// `bounds`.
  static func frame(in bounds: NSRect, inset: NSSize) -> NSRect {
    let margin = OpenedTabNoticeModel.margin
    let size = NSSize(
      width: TabListLayout.panelWidth + 2 * margin,
      height: TabListLayout.panelHeight(rows: 1) + 2 * margin)
    return NSRect(
      x: bounds.maxX - inset.width + margin - size.width,
      y: bounds.maxY - inset.height + margin - size.height, width: size.width,
      height: size.height)
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    isHidden = true
    alphaValue = 0
    let hostingView = NSHostingView(
      rootView: CloseWindowNoticeView(model: model))
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  /// Drops into place as it fades in, or if it's showing, stays a while
  /// longer.
  func show() {
    pendingDismissal?.cancel()
    let dismissal = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.dismiss() }
    }
    pendingDismissal = dismissal
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SlowMotion.duration(Metrics.holdDuration),
      execute: dismissal)
    guard !isShown else {
      return
    }
    isShown = true
    showings += 1
    isHidden = false
    withAnimation(.spring(duration: 0.35, bounce: 0).slowMotion) {
      model.isShown = true
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Metrics.fadeInDuration
      animator().alphaValue = 1
    }
    NSAccessibility.post(
      element: window ?? NSApp as Any, notification: .announcementRequested,
      userInfo: [
        .announcement: CloseWindowNoticeView.accessibilityText,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])
  }

  /// Lifts away as it fades out.
  func dismiss() {
    guard isShown else {
      return
    }
    isShown = false
    pendingDismissal?.cancel()
    pendingDismissal = nil
    let showing = showings
    withAnimation(.easeIn(duration: Metrics.fadeOutDuration).slowMotion) {
      model.isShown = false
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Metrics.fadeOutDuration
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isShown, self.showings == showing else {
          return
        }
        self.isHidden = true
      }
    }
  }
}

@MainActor
@Observable
final class CloseWindowNoticeModel {
  var isShown = false
}

/// A panel one tab row high, with the shortcut picked out.
struct CloseWindowNoticeView: View {
  static let accessibilityText = "Press Command-W again to close the window"

  let model: CloseWindowNoticeModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let key = Text("⌘W").fontWeight(.semibold).foregroundStyle(.primary)
    ZStack {
      PanelShadow(cornerRadius: TabListLayout.cornerRadius)
      RimmedGlass(
        cornerRadius: TabListLayout.cornerRadius,
        rimWidth: TabListLayout.rimWidth)
      Text("\(key) again to close window")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(
      width: TabListLayout.panelWidth,
      height: TabListLayout.panelHeight(rows: 1)
    )
    .offset(
      y: model.isShown || reduceMotion ? 0 : -OpenedTabNoticeModel.travel)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.accessibilityText)
  }
}
