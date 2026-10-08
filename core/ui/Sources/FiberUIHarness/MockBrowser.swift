import AppKit
import FiberBridge

/// Plays the part of //fiber/browser for one window.
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
    "recipes.example/ramen",
    "forum.example/t/keeping-a-chromium-fork-rebased-on-stable/4821?page=2",
    "bank.example/accounts", "travel.example/flights",
    "design.example/files/toolbar", "chat.example/general",
    "papers.example/abs/2609.01234v3?context=cs.IR&from=search",
    "store.example/app/fiber",
  ]

  /// `count` URLs: home, then made-up sites.
  static func sampleURLs(count: Int) -> [String] {
    [homeURL]
      + (0..<max(count - 1, 0)).map {
        "https://\(sampleSites[$0 % sampleSites.count])"
      }
  }

  let isIncognito: Bool
  // Set once `self` exists to be the window's actions.
  private var ui: (any FiberWindow)!
  private weak var app: HarnessAppDelegate?
  /// Its profile's.
  private let tabIndex: any FiberTabIndex
  private(set) var tabs: [MockTab] = []
  private var activeTab: MockTab!
  /// The pins open here, by ID. Their tabs come first, as in Chrome's tab
  /// strip.
  private var pinTabs: [String: MockTab] = [:]
  /// The profile's, which an Incognito window has none of.
  private var pins: MockPins? { isIncognito ? nil : app?.pins }
  private var dialog: (any FiberJavaScriptDialog)?
  /// Each tab's prompt, by tab ID, and the window's.
  private var tabPrompts:
    [Int: (prompt: any FiberPrompt, actions: PromptActions)] = [:]
  private var windowPrompt: (prompt: any FiberPrompt, actions: PromptActions)?
  private var controlsVisible = true
  private var omnibox: MockOmnibox!
  private var extensions: MockExtensions!
  /// Made the first time the window finds, as in Chrome.
  private var madeFindBar: MockFindBar?
  private var findBar: MockFindBar {
    if let madeFindBar {
      return madeFindBar
    }
    let findBar = MockFindBar(
      ui: ui.findBar, tab: activeTab,
      focusPage: { [weak self] in self?.focusPage() })
    madeFindBar = findBar
    return findBar
  }

  init(urls: [String], isIncognito: Bool, app: HarnessAppDelegate) {
    self.isIncognito = isIncognito
    self.app = app
    tabIndex = isIncognito ? app.incognitoTabIndex : app.tabIndex
    super.init()
    ui = FiberWindowFactory.window(
      withFrame: .zero, actions: self, tabIndex: tabIndex,
      incognito: isIncognito)
    omnibox = MockOmnibox(
      ui: ui.omnibox,
      currentURL: { [weak self] in
        guard let self, self.activeTab.url != Self.newTabURL else {
          return ""
        }
        return self.activeTab.url
      },
      open: { [weak self] input, event in
        self?.navigate(toInput: input, event: event)
      })
    ui.omnibox.actions = omnibox
    extensions = MockExtensions(ui: ui.extensions, window: ui.window) {
      [weak self] in self?.activeTab.id ?? 0
    }
    // Incognito's profile has downloads of its own, none so far.
    if !isIncognito {
      app.downloads.attach(ui.downloads)
    }
    for url in urls {
      openTab(url, activate: true)
    }
    pinsDidChange()
  }

  var window: NSWindow { ui.window }

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

  func pressSadTabButton() {
    reload(with: nil)
  }

  func openSadTabHelp() {}

  func focusPage() {
    ui.window.makeFirstResponder(activeTab.page)
  }

  func restoreFocus() {
    if activeTab.url == Self.newTabURL {
      ui.omnibox.focus(userInitiated: false)
    } else {
      focusPage()
    }
  }

  func selectTab(withID tabID: Int) {
    guard let tab = tabs.first(where: { $0.id == tabID }) else {
      app?.selectTab(withID: tabID)
      return
    }
    activate(tab)
  }

  func restore(_ restorableID: String, showingPageAt pageIndex: Int) {
    app?.restore(restorableID, showingPageAt: pageIndex)
  }

  func revealText(_ text: String, inTabWithID tabID: Int) {
    selectTab(withID: tabID)
    app?.browser(withTab: tabID)?.tabs.first { $0.id == tabID }?.page.find(text)
  }

  func closeTab(withID tabID: Int) {
    guard let tab = tabs.first(where: { $0.id == tabID }) else {
      return
    }
    // Like Fiber, the last tab leaves a New Tab page, which stays.
    let isLast = tabs.count == 1
    if isLast && tab.url == Self.newTabURL {
      restoreFocus()
      return
    }
    let leave = { [weak self] in
      if isLast {
        self?.openTab(Self.newTabURL, activate: false)
      }
      self?.close(tab)
    }
    guard tab.page.asksBeforeLeaving else {
      leave()
      return
    }
    confirmLeaving(tab, then: leave)
  }

  func pinTab(withID tabID: Int) {
    guard let pins, let tab = tabs.first(where: { $0.id == tabID }),
      !pinTabs.values.contains(tab)
    else {
      return
    }
    let id = pins.add(url: tab.url, title: tab.page.title)
    pinTabs[id] = tab
    pinsDidChange()
  }

  func openPin(withID pinID: String) {
    if let tab = pinTabs[pinID] {
      activate(tab)
      return
    }
    guard let pin = pins?.pin(withID: pinID) else {
      return
    }
    pinTabs[pinID] = openTab(pin.url, activate: true)
    pinsDidChange()
  }

  func resetPin(withID pinID: String) {
    guard let tab = pinTabs[pinID], let pin = pins?.pin(withID: pinID) else {
      openPin(withID: pinID)
      return
    }
    activate(tab)
    open(pin.url, in: tab)
  }

  func updateURLOfPin(withID pinID: String) {
    guard let tab = pinTabs[pinID] else {
      return
    }
    pins?.update(pinID, url: tab.url, title: tab.page.title)
  }

  func unpinPin(withID pinID: String) {
    pins?.remove(pinID)
  }

  func movePin(withID pinID: String, to index: Int) {
    pins?.move(pinID, to: index)
  }

  /// The pins changed, here or in another window: tabs of pins that are
  /// gone stay, as ordinary tabs, and the rest keep the pins' order.
  func pinsDidChange() {
    guard let pins else {
      return
    }
    pinTabs = pinTabs.filter { pins.pin(withID: $0.key) != nil }
    let pinned = pins.pins.compactMap { pinTabs[$0.id] }
    tabs = pinned + tabs.filter { !pinned.contains($0) }
    if activeTab != nil {
      pushTabs()
    }
  }

  func canRun(_ command: FiberCommand) -> Bool {
    switch command {
    case .keyPassthrough:
      activeTab.url != Self.newTabURL && activeTab.keyPassthroughHost == nil
    default:
      true
    }
  }

  func run(_ command: FiberCommand) {
    switch command {
    case .newTab:
      newTab(nil)
    case .print:
      NSPrintOperation(view: activeTab.page).runModal(
        for: ui.window, delegate: nil, didRun: nil, contextInfo: nil)
    case .keyPassthrough:
      guard canRun(command) else {
        return
      }
      activeTab.keyPassthroughHost = URL(string: activeTab.url)?.host() ?? ""
      pushPageState()
    @unknown default:
      break
    }
  }

  func endKeyPassthrough() {
    activeTab.keyPassthroughHost = nil
    pushPageState()
  }

  // The mock's pages take no keys.
  func performReservedKeyEquivalent(_ event: NSEvent) -> Bool {
    false
  }

  func commandPaletteDidOpen() {}

  func capturePageThumbnail(_ completion: @escaping (CGImage?) -> Void) {
    let thumbnail = activeTab.page.thumbnail()
    DispatchQueue.main.async { completion(thumbnail) }
  }

  func windowShouldClose() {
    guard let tab = tabs.first(where: \.page.asksBeforeLeaving) else {
      close()
      return
    }
    confirmLeaving(tab) { [weak self] in self?.close() }
  }

  func windowDidBecomeMain() {}

  func windowDidResignMain() {}

  func windowDidChangeFullScreen() {}

  func windowDidChangeFrame() {}

  // MARK: Menu actions (forwarded by the window)

  @objc func newTab(_ sender: Any?) {
    openTab(Self.newTabURL, activate: true)
  }

  @objc func closeTab(_ sender: Any?) {
    closeTab(withID: activeTab.id)
  }

  @objc func reloadPage(_ sender: Any?) {
    reload(with: nil)
  }

  @objc func simulateExtensionInstall(_ sender: Any?) {
    extensions.simulateInstall()
  }

  @objc func simulateExtensionWindow(_ sender: Any?) {
    extensions.openWindow()
  }

  @objc func toggleControls(_ sender: Any?) {
    controlsVisible.toggle()
    ui.setControlsVisible(controlsVisible)
  }

  @objc func openLocation(_ sender: Any?) {
    ui.omnibox.focus(userInitiated: true)
  }

  @objc func findInPage(_ sender: Any?) {
    findBar.open()
  }

  @objc func findNextInPage(_ sender: Any?) {
    findBar.open(findNext: true)
  }

  @objc func findPreviousInPage(_ sender: Any?) {
    findBar.open(findNext: true, forward: false)
  }

  /// Opens the find bar with `query` typed in it.
  func openFindBar(typing query: String) {
    findBar.open()
    (ui.window.firstResponder as? NSTextView)?.insertText(
      query, replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  // MARK: Harness controls

  /// Opens made-up sites, or closes tabs from the end, until there are
  /// `count`.
  func setTabCount(_ count: Int) {
    while tabs.count < count {
      openTab(Self.sampleURLs(count: tabs.count + 1).last!, activate: false)
    }
    while tabs.count > max(count, 1), let tab = tabs.last {
      close(tab)
    }
  }

  /// What `sample` asks, on the active tab or as the window's.
  func showPrompt(_ sample: PromptSample) {
    guard
      let content = sample.content(
        site: URL(string: activeTab.url)?.host() ?? activeTab.url)
    else {
      return
    }
    showPrompt(content, onTab: sample.isWindows ? nil : activeTab) { button in
      print(
        "\(sample.label): \(button.map { "button \($0)" } ?? "dismissed")")
    }
  }

  /// Asks on `tab`'s page, or, without one, as the window's prompt.
  private func showPrompt(
    _ content: FiberPromptContent, onTab tab: MockTab?,
    then answered: @escaping (Int?) -> Void
  ) {
    guard let tab else {
      let actions = PromptActions { [weak self] button in
        self?.windowPrompt = nil
        answered(button)
      }
      windowPrompt = (
        FiberPromptFactory.prompt(
          with: content, window: ui.window, actions: actions),
        actions
      )
      return
    }
    let tabID = tab.id
    let actions = PromptActions { [weak self] button in
      self?.tabPrompts[tabID] = nil
      answered(button)
    }
    tabPrompts[tabID] = (
      FiberPromptFactory.prompt(
        with: content, tabID: tabID, window: ui.window, actions: actions),
      actions
    )
  }

  // MARK: Omnibox

  /// Opens what the user picked in the omnibar: a URL, or a search.
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

  // MARK: The page's requests

  func linkHovered(_ url: String?) {
    ui.setStatusText(url ?? "")
  }

  func pointerMoved() {
    ui.pointerMovedOverPage()
  }

  func linkClicked(_ url: String, event: NSEvent?) {
    if opensElsewhere(event) {
      // Like Command-clicking a link in Chrome: a new tab in the background,
      // or in front with Shift.
      openTabFromLink(
        url, inFront: event?.modifierFlags.contains(.shift) == true)
    } else {
      open(url, in: activeTab)
    }
  }

  /// As a link opening a new tab does (`target="_blank"`, or
  /// Command-clicked): a tab opened from the active one, in front of it or
  /// behind.
  func openTabFromLink(_ url: String, inFront: Bool) {
    let opener = activeTab!
    let tab = openTab(url, activate: inFront)
    ui.didOpenTab(withID: tab.id, fromTabWithID: opener.id)
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

  /// Asks on `tab`'s page, as Chrome does for its beforeunload handler,
  /// bringing it forward.
  private func confirmLeaving(
    _ tab: MockTab, then leave: @escaping () -> Void
  ) {
    activate(tab)
    showPrompt(
      PromptSample.leaveSite.content(
        site: URL(string: tab.url)?.host() ?? tab.url)!,
      onTab: tab
    ) { button in
      if button == 0 {
        leave()
      }
    }
  }


  @discardableResult
  private func openTab(_ url: String, activate: Bool) -> MockTab {
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
    return tab
  }

  /// Brings the window forward, showing the tab.
  func show(tabWithID tabID: Int) {
    if let tab = tabs.first(where: { $0.id == tabID }) {
      activate(tab)
    }
    show()
  }

  private func activate(_ tab: MockTab) {
    guard tab !== activeTab else {
      return
    }
    // Switching tabs dismisses the page's dialog, as in Chrome.
    dialog?.close()
    activeTab = tab
    tab.lastActive = Date()
    ui.setContentsView(tab.page)
    ui.hideStatusText()
    madeFindBar?.tabDidActivate(tab)
    pushPageState()
    pushTabs()
    ui.setLoading(tab.isLoading, progress: tab.progress)
    // As Chrome does on switching tabs, once the window's showing.
    if ui.window.isVisible {
      restoreFocus()
    }
  }

  private func close(_ tab: MockTab) {
    guard let index = tabs.firstIndex(of: tab) else {
      return
    }
    tab.loadTimer?.invalidate()
    tabs.remove(at: index)
    pinTabs = pinTabs.filter { $0.value !== tab }
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
    tab.snapshots[tab.index] = tab.page.snapshot()
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
    activeTab.snapshots[activeTab.index] = activeTab.page.snapshot()
    activeTab.index = newIndex
    startLoading(activeTab)
  }

  // MARK: History swipes

  private var swipeScroll = NSSize.zero
  private var isSwiping = false
  private var swipeTimer: Timer?

  /// Swipes between pages as FiberHistorySwiper does, minus asking the renderer
  /// first (the mock page doesn't scroll). Returns whether the swipe has the
  /// event.
  func swipe(with event: NSEvent) -> Bool {
    if event.phase == .began {
      swipeScroll = .zero
    }
    guard event.phase == .changed, !isSwiping,
      NSEvent.isSwipeTrackingFromScrollEventsEnabled
    else {
      return isSwiping
    }
    swipeScroll.width += event.scrollingDeltaX
    swipeScroll.height += event.scrollingDeltaY
    guard abs(swipeScroll.width) > abs(swipeScroll.height) else {
      return false
    }
    let back = swipeScroll.width > 0
    let tab = activeTab!
    let target = tab.index + (back ? -1 : 1)
    guard tab.history.indices.contains(target) else {
      return false
    }
    isSwiping = true
    // Once the user lets go, the UI carries the swipe on and says whether it
    // landed; AppKit's tracking carries on unheeded until it's done.
    var released = false
    var settled = false
    var tracked = false
    event.trackSwipeEvent(
      options: .lockDirection, dampenAmountThresholdMin: -1, max: 1
    ) { [weak self] amount, phase, isComplete, _ in
      MainActor.assumeIsolated {
        guard let self else {
          return
        }
        if phase == .began {
          self.ui.beginHistorySwipe(
            in: back ? .back : .forward, snapshot: tab.snapshots[target])
        }
        if !released {
          self.ui.updateHistorySwipe(abs(amount))
          if phase == .ended || phase == .cancelled {
            released = true
            self.ui.releaseHistorySwipe { landed in
              settled = true
              self.isSwiping = !tracked
              self.finishSwipe(to: target, committed: landed)
            }
          }
        }
        if isComplete {
          tracked = true
          if !released {
            self.finishSwipe(to: target, committed: false)
          }
          self.isSwiping = released && !settled
        }
      }
    }
    return true
  }

  @objc func simulateSwipeBack(_ sender: Any?) {
    simulateSwipe(back: true)
  }

  @objc func simulateSwipeForward(_ sender: Any?) {
    simulateSwipe(back: false)
  }

  /// A swipe without a trackpad: dragged halfway over a second, then let go.
  private func simulateSwipe(back: Bool) {
    let tab = activeTab!
    let target = tab.index + (back ? -1 : 1)
    guard tab.history.indices.contains(target), !isSwiping else {
      return
    }
    isSwiping = true
    ui.beginHistorySwipe(
      in: back ? .back : .forward, snapshot: tab.snapshots[target])
    let start = Date()
    swipeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else {
          return
        }
        let t = Date().timeIntervalSince(start)
        self.ui.updateHistorySwipe(0.5 * min(t / 1.2, 1))
        guard t >= 1.2 else {
          return
        }
        self.swipeTimer?.invalidate()
        self.swipeTimer = nil
        self.ui.releaseHistorySwipe { landed in
          self.isSwiping = false
          self.finishSwipe(to: target, committed: landed)
        }
      }
    }
  }

  private func finishSwipe(to index: Int, committed: Bool) {
    ui.endHistorySwipeNavigating(committed)
    guard committed else {
      return
    }
    go(to: index, event: nil)
    // The mock page shows its new URL at once; a real one takes a moment.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      MainActor.assumeIsolated { self?.ui.finishHistorySwipeNavigation() }
    }
  }

  private func startLoading(_ tab: MockTab) {
    // Navigating away dismisses the page's dialog, as in Chrome.
    if tab === activeTab {
      dialog?.close()
    }
    madeFindBar?.pageWillChange(in: tab)
    // Key passthrough ends on another site.
    if let host = tab.keyPassthroughHost, URL(string: tab.url)?.host() != host {
      tab.keyPassthroughHost = nil
    }
    tab.loadTimer?.invalidate()
    tab.loadStart = Date()
    tab.page.show(url: tab.url, loaded: false)
    // The browser drops a page's text once it's left.
    tabIndex.setPageText("", forTabWithID: tab.id)
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
    tabIndex.setPageText(
      MockPages.page(for: tab.url)?.text ?? "", forTabWithID: tab.id)
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
        displayURL: isNewTabPage ? "" : host, title: tab.page.title,
        canGoBack: tab.index > 0,
        canGoForward: tab.index < tab.history.count - 1,
        loading: tab.isLoading, newTabPage: isNewTabPage, sadTab: nil,
        keyPassthrough: tab.keyPassthroughHost != nil))
  }

  /// The window's tabs, as the UI shows them.
  var tabStates: [FiberTabState] {
    tabs.map {
      FiberTabState(
        id: $0.id, title: $0.page.title, url: Self.displayURL($0.url),
        origin: Self.displayOrigin($0.url),
        favicon: MockFavicon.image(for: $0.url), loading: $0.isLoading,
        lastActiveTime: $0.lastActive)
    }
  }

  private func pushTabs() {
    ui.setTabs(tabStates, activeTabID: activeTab.id)
    if let pins {
      ui.setPins(
        pins.pins.map { pin in
          let tab = pinTabs[pin.id]
          return FiberPinState(
            id: pin.id, title: pin.title, url: Self.displayURL(pin.url),
            favicon: MockFavicon.image(for: pin.url), tabID: tab?.id ?? 0,
            loading: tab?.isLoading ?? false, atPinnedURL: tab?.url == pin.url)
        })
    }
    app?.tabsDidChange()
  }

  /// `url` as Chrome shows it: no "https://", "www." or lone "/".
  static func displayURL(_ url: String) -> String {
    var display = url
    for prefix in ["https://", "http://", "www."]
    where display.hasPrefix(prefix) {
      display.removeFirst(prefix.count)
    }
    if display.last == "/",
      display.firstIndex(of: "/") == display.indices.last
    {
      display.removeLast()
    }
    return display
  }

  /// The start of `displayURL(url)` through its host.
  private static func displayOrigin(_ url: String) -> String {
    let display = displayURL(url)
    let host = display.range(of: "://")?.upperBound ?? display.startIndex
    return String(
      display[..<(display[host...].firstIndex(of: "/") ?? display.endIndex)])
  }

  /// Opens the command palette with `query` typed in it.
  func openCommandPalette(typing query: String) {
    ui.showCommandPalette()
    (ui.window.firstResponder as? NSTextView)?.insertText(
      query, replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  private func close() {
    for tab in tabs {
      tab.loadTimer?.invalidate()
    }
    extensions.stop()
    ui.window.close()
    app?.browserDidClose(self)
  }
}

@MainActor
final class MockTab: Equatable {
  private static let loadDuration: TimeInterval = 0.8
  private static var lastID = 0

  let id: Int
  let page = MockPageView()
  var history: [String] = []
  var index = -1
  /// What each page in `history` looked like when it was left.
  var snapshots: [Int: NSImage] = [:]
  var loadStart: Date?
  var loadTimer: Timer?
  var lastActive = Date()
  /// Where the tab was when key passthrough started, while it has it.
  var keyPassthroughHost: String?

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
