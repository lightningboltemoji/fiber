import AppKit
import FiberBridge

/// Plays the part of //fiber/browser for one window: keeps tabs of fake pages,
/// each with its own history, "loads" them with simulated progress, and shows
/// JavaScript dialogs, all through the bridge.
@MainActor
final class MockBrowser: NSObject, FiberWindowActions {
  static let homeURL = "https://fiber.example/"
  static let newTabURL = "chrome://newtab/"
  private static let sampleSites = [
    "news.example/front", "mail.example/inbox", "docs.example/spec/tab-picker",
    "video.example/watch?v=glass", "maps.example/@37.77,-122.41",
    "shop.example/cart", "wiki.example/Liquid_glass", "code.example/fiber/pulls",
    "music.example/playlist/focus", "weather.example/today",
    "calendar.example/week", "photos.example/albums/summer",
    "recipes.example/ramen", "forum.example/t/chromium-forks",
    "bank.example/accounts", "travel.example/flights",
    "design.example/files/toolbar", "chat.example/general",
    "papers.example/abs/2609.01234", "store.example/app/fiber",
  ]

  /// `count` URLs: home, then made-up sites.
  static func sampleURLs(count: Int) -> [String] {
    [homeURL]
      + (0..<max(count - 1, 0)).map {
        "https://\(sampleSites[$0 % sampleSites.count])"
      }
  }

  // Set once `self` exists to be the window's actions.
  private var ui: (any FiberWindow)!
  private weak var app: HarnessAppDelegate?
  private var tabs: [MockTab] = []
  private var activeTab: MockTab!
  private var dialog: (any FiberJavaScriptDialog)?
  private var controlsVisible = true

  init(urls: [String], app: HarnessAppDelegate) {
    self.app = app
    super.init()
    ui = FiberWindowFactory.window(withFrame: .zero, actions: self)
    for url in urls {
      openTab(url, activate: true)
    }
  }

  func show() {
    ui.window.makeKeyAndOrderFront(nil)
  }

  // MARK: FiberWindowActions

  func goBack(with event: NSEvent?) {
    go(to: activeTab.index - 1, event: event)
  }

  func goForward(with event: NSEvent?) {
    go(to: activeTab.index + 1, event: event)
  }

  func reload(with event: NSEvent?) {
    startLoading(activeTab)
  }

  func stopLoading() {
    finishLoading(activeTab)
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
      openTab(url, activate: true)
    } else {
      open(url, in: activeTab)
      focusPage()
    }
  }

  func focusPage() {
    ui.window.makeFirstResponder(activeTab.page)
  }

  func selectTab(withID tabID: Int) {
    guard let tab = tabs.first(where: { $0.id == tabID }) else {
      return
    }
    activate(tab)
  }

  func windowShouldClose() {
    guard tabs.contains(where: \.page.asksBeforeLeaving) else {
      close()
      return
    }
    confirmLeaving { [weak self] in self?.close() }
  }

  func windowDidBecomeMain() {}

  func windowDidResignMain() {}

  func windowDidChangeFullScreen() {}

  // MARK: Menu actions (forwarded by the window)

  @objc func newTab(_ sender: Any?) {
    openTab(Self.newTabURL, activate: true)
    ui.showCommandPalette()
  }

  @objc func closeTab(_ sender: Any?) {
    let tab = activeTab!
    guard tab.page.asksBeforeLeaving else {
      close(tab)
      return
    }
    confirmLeaving { [weak self] in self?.close(tab) }
  }

  @objc func reloadPage(_ sender: Any?) {
    reload(with: nil)
  }

  @objc func toggleControls(_ sender: Any?) {
    controlsVisible.toggle()
    ui.setControlsVisible(controlsVisible)
  }

  @objc func openLocation(_ sender: Any?) {
    ui.showCommandPalette()
  }

  // MARK: The page's requests

  func linkHovered(_ url: String?) {
    ui.setStatusText(url ?? "")
  }

  func linkClicked(_ url: String, event: NSEvent?) {
    if opensElsewhere(event) {
      // Like Command-clicking a link in Chrome: a new tab in the background.
      openTab(url, activate: false)
    } else {
      open(url, in: activeTab)
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

  private func confirmLeaving(then leave: @escaping () -> Void) {
    showDialog(
      .confirm, title: "Leave site?",
      message: "Changes you made may not be saved.", accept: "Leave"
    ) { result in
      if case .accepted = result {
        leave()
      }
    }
  }

  private func openTab(_ url: String, activate: Bool) {
    let tab = MockTab()
    tab.page.browser = self
    tab.history = [url]
    tab.index = 0
    // Next to the active tab, as Chrome opens tabs from links.
    let index = activeTab.flatMap { tabs.firstIndex(of: $0) } ?? tabs.count - 1
    tabs.insert(tab, at: index + 1)
    if activate || activeTab == nil {
      self.activate(tab)
    }
    startLoading(tab)
  }

  private func activate(_ tab: MockTab) {
    guard tab !== activeTab else {
      return
    }
    // Switching tabs dismisses the page's dialog, as in Chrome.
    dialog?.close()
    activeTab = tab
    ui.setContentsView(tab.page)
    pushPageState()
    pushTabs()
    ui.setLoading(tab.isLoading, progress: tab.progress)
  }

  private func close(_ tab: MockTab) {
    guard let index = tabs.firstIndex(of: tab) else {
      return
    }
    tab.loadTimer?.invalidate()
    tabs.remove(at: index)
    guard !tabs.isEmpty else {
      close()
      return
    }
    if tab === activeTab {
      activate(tabs[min(index, tabs.count - 1)])
    } else {
      pushTabs()
    }
  }

  private func open(_ url: String, in tab: MockTab) {
    tab.history.removeSubrange((tab.index + 1)...)
    tab.history.append(url)
    tab.index += 1
    startLoading(tab)
  }

  private func go(to newIndex: Int, event: NSEvent?) {
    guard activeTab.history.indices.contains(newIndex) else {
      return
    }
    if opensElsewhere(event) {
      openTab(activeTab.history[newIndex], activate: false)
      return
    }
    activeTab.index = newIndex
    startLoading(activeTab)
  }

  private func startLoading(_ tab: MockTab) {
    // Navigating away dismisses the page's dialog, as in Chrome.
    if tab === activeTab {
      dialog?.close()
    }
    tab.loadTimer?.invalidate()
    tab.loadStart = Date()
    tab.page.show(url: tab.url, loaded: false)
    tabDidChange(tab)
    tab.loadTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true)
    { [weak self, weak tab] _ in
      MainActor.assumeIsolated {
        if let self, let tab {
          self.loadTick(tab)
        }
      }
    }
  }

  private func loadTick(_ tab: MockTab) {
    guard tab.isLoading else {
      return
    }
    if tab.progress >= 1 {
      finishLoading(tab)
    } else if tab === activeTab {
      ui.setLoading(true, progress: tab.progress)
    }
  }

  private func finishLoading(_ tab: MockTab) {
    tab.loadTimer?.invalidate()
    tab.loadTimer = nil
    tab.loadStart = nil
    tab.page.show(url: tab.url, loaded: true)
    tabDidChange(tab)
  }

  private func tabDidChange(_ tab: MockTab) {
    pushTabs()
    if tab === activeTab {
      pushPageState()
      ui.setLoading(tab.isLoading, progress: tab.progress)
    }
  }

  private func pushPageState() {
    let tab = activeTab!
    // Like Chrome, the New Tab page doesn't show its URL.
    let isNewTabPage = tab.url == Self.newTabURL
    let host = URL(string: tab.url)?.host() ?? tab.url
    ui.setPageState(
      FiberPageState(
        url: isNewTabPage ? "" : tab.url,
        displayURL: isNewTabPage ? "" : host, title: tab.page.title,
        canGoBack: tab.index > 0,
        canGoForward: tab.index < tab.history.count - 1,
        loading: tab.isLoading, newTabPage: isNewTabPage))
  }

  private func pushTabs() {
    ui.setTabs(
      tabs.map {
        FiberTabState(
          id: $0.id, title: $0.page.title, favicon: nil, loading: $0.isLoading)
      }, activeTabID: activeTab.id)
  }

  private func close() {
    for tab in tabs {
      tab.loadTimer?.invalidate()
    }
    ui.window.close()
    app?.browserDidClose(self)
  }
}

/// A tab: its page and history, and its load in progress.
@MainActor
private final class MockTab: Equatable {
  private static let loadDuration: TimeInterval = 0.8
  private static var lastID = 0

  let id: Int
  let page = MockPageView()
  var history: [String] = []
  var index = -1
  var loadStart: Date?
  var loadTimer: Timer?

  init() {
    Self.lastID += 1
    id = Self.lastID
  }

  var url: String { history[index] }
  var isLoading: Bool { loadStart != nil }

  /// Simulated load progress, from 0.1 when the load starts to 1.
  var progress: Double {
    guard let loadStart else {
      return 1
    }
    let elapsed = Date().timeIntervalSince(loadStart) / Self.loadDuration
    return 0.1 + 0.9 * min(elapsed, 1)
  }

  nonisolated static func == (lhs: MockTab, rhs: MockTab) -> Bool {
    lhs === rhs
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
