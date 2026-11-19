import AppKit
import SwiftUI

/// In OpenedTabNotice's place and glass, after a key that would close
/// something doesn't: that pressing it again does. Command-W on the window's
/// last tab, a New Tab page, which stays, then closes the window, and Escape
/// that a peek's page used closes the peek. Clicks go through it, and it goes
/// after a moment.
@MainActor
final class PressAgainNotice: NSView {
  enum Action {
    case closeWindow
    case closePeek
  }

  private enum Metrics {
    /// How long it stays after the last try.
    static let holdDuration: TimeInterval = 2.5
    static let fadeInDuration: TimeInterval = 0.2
    static let fadeOutDuration: TimeInterval = 0.3
  }

  private(set) var isShown = false
  private let model = PressAgainNoticeModel()
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
      rootView: PressAgainNoticeView(model: model))
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

  func isShown(for action: Action) -> Bool {
    isShown && model.action == action
  }

  /// Drops into place as it fades in, or if it's showing, stays a while
  /// longer.
  func show(_ action: Action) {
    model.action = action
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
        .announcement: PressAgainNoticeView.accessibilityText(for: action),
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])
  }

  /// Lifts away as it fades out, if it's about `action`, or any.
  func dismiss(_ action: Action? = nil) {
    guard isShown, action.map({ $0 == model.action }) ?? true else {
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
final class PressAgainNoticeModel {
  var isShown = false
  var action = PressAgainNotice.Action.closeWindow
}

/// A panel one tab row high, with the key picked out.
struct PressAgainNoticeView: View {
  static func accessibilityText(for action: PressAgainNotice.Action) -> String {
    switch action {
    case .closeWindow: "Press Command-W again to close the window"
    case .closePeek: "Press Escape again to close the peek"
    }
  }

  let model: PressAgainNoticeModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let (keyName, outcome) =
      switch model.action {
      case .closeWindow: ("⌘W", "close window")
      case .closePeek: ("esc", "close peek")
      }
    let key = Text(keyName).fontWeight(.semibold).foregroundStyle(.primary)
    ZStack {
      PanelShadow(cornerRadius: TabListLayout.cornerRadius)
      RimmedGlass(
        cornerRadius: TabListLayout.cornerRadius,
        rimWidth: TabListLayout.rimWidth)
      Text("\(key) again to \(outcome)")
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
    .accessibilityLabel(Self.accessibilityText(for: model.action))
  }
}
