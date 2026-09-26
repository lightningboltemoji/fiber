import AppKit
import FiberBridge

/// Plays the part of //fiber/browser for one window: keeps a history of fake
/// pages, "loads" them with simulated progress, and shows JavaScript dialogs,
/// all through the bridge.
@MainActor
final class MockBrowser: NSObject, FiberWindowActions {
  static let homeURL = "https://fiber.example/"
  private static let loadDuration: TimeInterval = 0.8

  // Set once `self` exists to be the window's actions.
  private var ui: (any FiberWindow)!
  private let page = MockPageView()
  private weak var app: HarnessAppDelegate?
  private var history: [String] = []
  private var index = -1
  private var loadStart: Date?
  private var loadTimer: Timer?
  private var dialog: (any FiberJavaScriptDialog)?
  private var toolbarVisible = true

  init(url: String, app: HarnessAppDelegate) {
    self.app = app
    super.init()
    ui = FiberWindowFactory.window(withFrame: .zero, actions: self)
    page.browser = self
    ui.setContentsView(page)
    open(url)
  }

  func show() {
    ui.window.makeKeyAndOrderFront(nil)
  }

  // MARK: FiberWindowActions

  func goBack(with event: NSEvent?) {
    go(to: index - 1, event: event)
  }

  func goForward(with event: NSEvent?) {
    go(to: index + 1, event: event)
  }

  func reload(with event: NSEvent?) {
    startLoading()
  }

  func stopLoading() {
    finishLoading()
  }

  func navigate(toInput input: String, event: NSEvent?) {
    let input = input.trimmingCharacters(in: .whitespaces)
    guard !input.isEmpty else {
      return
    }
    let url: String
    if input.contains("://") {
      url = input
    } else if input.contains("."), !input.contains(" ") {
      url = "https://\(input)/"
    } else {
      let query =
        input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      url = "https://search.example/?q=\(query ?? "")"
    }
    if opensElsewhere(event) {
      app?.openWindow(url: url)
    } else {
      open(url)
      focusPage()
    }
  }

  func focusPage() {
    ui.window.makeFirstResponder(page)
  }

  func windowShouldClose() {
    guard page.asksBeforeLeaving else {
      close()
      return
    }
    showDialog(
      .confirm, title: "Leave site?",
      message: "Changes you made may not be saved.", accept: "Leave"
    ) { [weak self] result in
      if case .accepted = result {
        self?.close()
      }
    }
  }

  func windowDidBecomeMain() {}

  func windowDidResignMain() {}

  func windowDidChangeFullScreen() {}

  // MARK: Menu actions (forwarded by the window)

  @objc func reloadPage(_ sender: Any?) {
    reload(with: nil)
  }

  @objc func toggleToolbar(_ sender: Any?) {
    toolbarVisible.toggle()
    ui.setToolbarVisible(toolbarVisible)
  }

  @objc func openLocation(_ sender: Any?) {
    ui.focusLocationBar()
  }

  // MARK: The page's requests

  func linkHovered(_ url: String?) {
    ui.setStatusText(url ?? "")
  }

  func linkClicked(_ url: String, event: NSEvent?) {
    if opensElsewhere(event) {
      app?.openWindow(url: url)
    } else {
      open(url)
    }
  }

  func showDialog(
    _ kind: FiberJavaScriptDialogKind, title: String, message: String,
    accept: String = "OK", defaultPromptText: String = "",
    completion: @escaping (MockDialogResult) -> Void
  ) {
    let content = FiberJavaScriptDialogContent(
      kind: kind, title: title, message: message,
      defaultPromptText: defaultPromptText, acceptButtonTitle: accept,
      cancelButtonTitle: "Cancel")
    let actions = MockDialogActions { [weak self] result in
      self?.dialog = nil
      completion(result)
    }
    dialog = FiberJavaScriptDialogFactory.dialog(
      with: content, window: ui.window, actions: actions)
  }

  // MARK: Private

  private func opensElsewhere(_ event: NSEvent?) -> Bool {
    event?.modifierFlags.contains(.command) ?? false
  }

  private func open(_ url: String) {
    history.removeSubrange((index + 1)...)
    history.append(url)
    index += 1
    startLoading()
  }

  private func go(to newIndex: Int, event: NSEvent?) {
    guard history.indices.contains(newIndex) else {
      return
    }
    if opensElsewhere(event) {
      app?.openWindow(url: history[newIndex])
      return
    }
    index = newIndex
    startLoading()
  }

  private func startLoading() {
    // Navigating away dismisses the page's dialog, as in Chrome.
    dialog?.close()
    loadTimer?.invalidate()
    loadStart = Date()
    page.show(url: history[index], loaded: false)
    pushPageState()
    ui.setLoading(true, progress: 0.1)
    loadTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
      _ in
      MainActor.assumeIsolated { self.loadTick() }
    }
  }

  private func loadTick() {
    guard let loadStart else {
      return
    }
    let progress = Date().timeIntervalSince(loadStart) / Self.loadDuration
    if progress >= 1 {
      finishLoading()
    } else {
      ui.setLoading(true, progress: 0.1 + 0.9 * progress)
    }
  }

  private func finishLoading() {
    loadTimer?.invalidate()
    loadTimer = nil
    loadStart = nil
    page.show(url: history[index], loaded: true)
    pushPageState()
    ui.setLoading(false, progress: 1)
  }

  private func pushPageState() {
    let url = history[index]
    let host = URL(string: url)?.host() ?? url
    ui.setPageState(
      FiberPageState(
        url: url, displayURL: host, title: page.title,
        canGoBack: index > 0, canGoForward: index < history.count - 1,
        loading: loadStart != nil))
  }

  private func close() {
    loadTimer?.invalidate()
    ui.window.close()
    app?.browserDidClose(self)
  }
}

enum MockDialogResult {
  case accepted(input: String)
  case cancelled
  case dismissed
}

/// Reports how a dialog ended to a closure.
private final class MockDialogActions: NSObject, FiberJavaScriptDialogActions {
  private let completion: (MockDialogResult) -> Void

  init(completion: @escaping (MockDialogResult) -> Void) {
    self.completion = completion
  }

  func dialogDidAccept(withInput input: String) {
    completion(.accepted(input: input))
  }

  func dialogDidCancel() {
    completion(.cancelled)
  }

  func dialogDidDismiss() {
    completion(.dismissed)
  }
}
