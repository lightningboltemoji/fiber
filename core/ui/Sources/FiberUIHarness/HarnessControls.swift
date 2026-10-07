import AppKit
import FiberBridge
import SwiftUI

/// The harness's own controls, in a panel beside the browser window they act
/// on: its tabs, the profile's pins, a prompt on its page, a tab opened from a
/// link on it, and how slowly the UI animates.
@MainActor
final class HarnessControls: NSObject, NSWindowDelegate {
  @Observable
  final class Model {
    var tabCount = 0
    var pinCount = 0
    var slowMotion = 1.0
    @ObservationIgnored var setTabCount: (Int) -> Void = { _ in }
    @ObservationIgnored var setPinCount: (Int) -> Void = { _ in }
    @ObservationIgnored var showPrompt: (PromptSample) -> Void = { _ in }
    /// In front, or behind.
    @ObservationIgnored var openTabFromLink: (Bool) -> Void = { _ in }
  }

  /// Between the panel and its window.
  private static let gap: CGFloat = 8

  let model = Model()
  private let panel: NSPanel
  /// The browser window it's beside.
  private weak var window: NSWindow?
  /// Off once its close button is pressed, so it stays closed.
  private var isShown = true

  override init() {
    panel = NSPanel(
      contentRect: .zero,
      styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
      backing: .buffered, defer: false)
    super.init()
    panel.title = "Harness"
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    // Its buttons and steppers work without taking the keyboard from the
    // browser window, whose prompt or overlay they may have just opened.
    panel.becomesKeyOnlyIfNeeded = true
    let hostingView = NSHostingView(rootView: ControlsView(model: model))
    panel.contentView = hostingView
    panel.setContentSize(hostingView.fittingSize)
    model.slowMotion = FiberSlowMotion.factor
  }

  /// Beside `window`, following it as it moves. Not its child window, which
  /// a capture of the window (`screencapture -l`) would include.
  func attach(to window: NSWindow) {
    guard window !== self.window else {
      return
    }
    let center = NotificationCenter.default
    if let old = self.window {
      center.removeObserver(self, name: nil, object: old)
    }
    self.window = window
    for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification]
    {
      center.addObserver(
        self, selector: #selector(windowDidChangeFrame(_:)), name: name,
        object: window)
    }
    if isShown {
      makeRoom(beside: window)
      place()
      panel.orderFront(nil)
    }
  }

  func show() {
    isShown = true
    place()
    panel.orderFront(nil)
  }

  func update(tabCount: Int, pinCount: Int) {
    model.tabCount = tabCount
    model.pinCount = pinCount
  }

  /// If neither side of `window` has room for the panel, moves it left to
  /// make some, as far as the screen allows.
  private func makeRoom(beside window: NSWindow) {
    let screen = visibleFrame(of: window)
    let width = panel.frame.width + Self.gap
    let frame = window.frame
    if frame.maxX + width > screen.maxX, frame.minX - width < screen.minX {
      window.setFrameOrigin(
        NSPoint(
          x: max(screen.maxX - width - frame.width, screen.minX),
          y: frame.minY))
    }
  }

  /// To the window's right, or its left if only that has room.
  private func place() {
    guard let window else {
      return
    }
    let screen = visibleFrame(of: window)
    let frame = window.frame
    let size = panel.frame.size
    let x =
      frame.maxX + Self.gap + size.width > screen.maxX
        && frame.minX - Self.gap - size.width >= screen.minX
      ? frame.minX - Self.gap - size.width : frame.maxX + Self.gap
    panel.setFrameOrigin(NSPoint(x: x, y: frame.maxY - size.height))
  }

  private func visibleFrame(of window: NSWindow) -> NSRect {
    (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
  }

  @objc private func windowDidChangeFrame(_ notification: Notification) {
    if isShown {
      place()
    }
  }

  func windowWillClose(_ notification: Notification) {
    isShown = false
  }
}

private struct ControlsView: View {
  private static let slowMotions = [1.0, 2, 5, 10]

  @Bindable var model: HarnessControls.Model

  var body: some View {
    Form {
      LabeledContent("Tabs:") {
        Stepper(
          value: Binding(
            get: { model.tabCount }, set: { model.setTabCount($0) }),
          in: 1...60
        ) { count(model.tabCount) }
      }
      LabeledContent("Pins:") {
        Stepper(
          value: Binding(
            get: { model.pinCount }, set: { model.setPinCount($0) }),
          in: 0...40
        ) { count(model.pinCount) }
      }
      LabeledContent("Prompt:") {
        Menu("Show") {
          Section("On the Tab") {
            samples(PromptSample.allCases.filter { !$0.isWindows })
          }
          Section("The Window's") {
            samples(PromptSample.allCases.filter(\.isWindows))
          }
        }
        .fixedSize()
      }
      LabeledContent("Link:") {
        HStack {
          Button("New Tab") { model.openTabFromLink(true) }
          Button("Background Tab") { model.openTabFromLink(false) }
        }
      }
      Picker("Slow Motion:", selection: $model.slowMotion) {
        ForEach(Self.slowMotions, id: \.self) { factor in
          Text("\(Int(factor))×").tag(factor)
        }
      }
      .pickerStyle(.segmented)
      .fixedSize()
      .onChange(of: model.slowMotion) { _, factor in
        FiberSlowMotion.factor = factor
      }
    }
    .formStyle(.columns)
    .padding(16)
  }

  private func samples(_ samples: [PromptSample]) -> some View {
    ForEach(samples, id: \.self) { sample in
      Button(sample.label) { model.showPrompt(sample) }
    }
  }

  /// Wide enough for two digits, so the stepper beside it stays put.
  private func count(_ value: Int) -> some View {
    Text("\(value)").monospacedDigit().frame(minWidth: 20, alignment: .leading)
  }
}
