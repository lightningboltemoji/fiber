// Runs Fiber's UI against a mock browser that uses the bridge exactly as
// //fiber/browser does, without Chromium. Flags: `--tabs N` (made-up sites),
// `--downloads N` (which quitting waits for), `--ask-before-leaving`,
// `--palette QUERY` (the command palette, open with QUERY typed),
// `--find QUERY` (the find bar, likewise), `--extension-window` (a window an extension opened, as its bubble),
// `--incognito` (the first window is Incognito, on the New Tab page),
// `--pins N` (made-up pinned sites, the first two open),
// `--overlay` (the tab overlay, as Command-S opens it),
// `--key-passthrough` (the active tab has key passthrough),
// `--profiles` (the profile switcher), `--new-profile` (its New Profile page),
// `--slow-motion N` (animations N times slower). Its own controls (see
// HarnessControls) sit beside the window last used.

import AppKit
import FiberBridge

let app = NSApplication.shared
let delegate = HarnessAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

@MainActor
final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
  private var browsers: [MockBrowser] = []
  /// Every window's tabs, as one profile's, and Incognito windows' as its
  /// Incognito profile's.
  let tabIndex = FiberTabIndexFactory.tabIndex()
  let incognitoTabIndex = FiberTabIndexFactory.tabIndex()
  /// The profile's pins, which its windows share.
  let pins = MockPins()
  private lazy var downloads = MockDownloads(count: launchDownloadCount)
  private lazy var profiles = MockProfiles(app: self)
  /// Set once the downloads are done, so the quit they held up goes ahead.
  private var isDoneWaiting = false
  private lazy var controls = makeControls()
  /// The window last used, which the controls act on.
  private weak var currentBrowser: MockBrowser?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()
    if let factor = launchValue(of: "--slow-motion").flatMap(Double.init) {
      FiberSlowMotion.factor = factor
    }
    pins.onChange = { [weak self] in
      for browser in self?.browsers ?? [] {
        browser.pinsDidChange()
      }
      self?.updateControls()
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(windowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification, object: nil)
    if CommandLine.arguments.contains("--incognito") {
      openWindow(
        urls: [MockBrowser.newTabURL]
          + MockBrowser.sampleURLs(count: launchTabCount).dropFirst(),
        isIncognito: true)
    } else {
      openWindow(urls: MockBrowser.sampleURLs(count: launchTabCount))
    }
    if let count = launchValue(of: "--pins").flatMap(Int.init), count > 0 {
      setPinCount(count)
      for pin in pins.pins.prefix(2) {
        browsers.last?.openPin(withID: pin.id)
      }
    }
    NSApp.activate()
    if CommandLine.arguments.contains("--overlay") {
      browsers.last?.window.toggleToolbarShown(nil)
    }
    if CommandLine.arguments.contains("--extension-window") {
      browsers.last?.simulateExtensionWindow(nil)
    }
    if CommandLine.arguments.contains("--key-passthrough") {
      browsers.last?.run(.keyPassthrough)
    }
    if CommandLine.arguments.contains("--profiles") {
      switchProfile(nil)
    } else if CommandLine.arguments.contains("--new-profile") {
      addProfile(nil)
    }
    if let query = launchValue(of: "--palette") {
      // Once the pages have loaded, so there's text to find.
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        MainActor.assumeIsolated {
          self?.browsers.last?.openCommandPalette(typing: query)
        }
      }
    }
    if let query = launchValue(of: "--find") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        MainActor.assumeIsolated {
          self?.browsers.last?.openFindBar(typing: query)
        }
      }
    }
  }

  // Like Chrome with Warn Before Quitting on: Command-Q quits only when held.
  func applicationShouldTerminate(_ sender: NSApplication)
    -> NSApplication.TerminateReply
  {
    if isDoneWaiting {
      return .terminateNow
    }
    if let event = NSApp.currentEvent, event.type == .keyDown,
      event.charactersIgnoringModifiers == "q",
      !FiberQuitConfirmation.run(with: event, announcement: "Hold ⌘Q to Quit")
    {
      return .terminateCancel
    }
    // Like Chrome, it waits for downloads, in the window last used.
    guard !downloads.isEmpty,
      let window = NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
    else {
      return .terminateNow
    }
    downloads.wait(in: window) { [weak self] proceed in
      if proceed {
        self?.isDoneWaiting = true
        NSApp.terminate(nil)
      } else {
        FiberQuitConfirmation.restoreWindows()
      }
    }
    return .terminateCancel
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication)
    -> Bool
  {
    true
  }

  private var launchDownloadCount: Int {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--downloads"),
      arguments.indices.contains(flag + 1),
      let count = Int(arguments[flag + 1])
    else {
      return 0
    }
    return max(count, 0)
  }

  private func launchValue(of flagName: String) -> String? {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: flagName),
      arguments.indices.contains(flag + 1)
    else {
      return nil
    }
    return arguments[flag + 1]
  }

  private var launchTabCount: Int {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--tabs"),
      arguments.indices.contains(flag + 1), let count = Int(arguments[flag + 1])
    else {
      return 1
    }
    return max(count, 1)
  }

  func openWindow(urls: [String], isIncognito: Bool = false) {
    let browser = MockBrowser(urls: urls, isIncognito: isIncognito, app: self)
    browsers.append(browser)
    tabsDidChange()
    browser.show()
    // Even if it isn't key, as when the harness starts in the background.
    makeCurrent(browser)
  }

  func browserDidClose(_ browser: MockBrowser) {
    browsers.removeAll { $0 === browser }
    if currentBrowser == nil || currentBrowser === browser,
      let last = browsers.last
    {
      makeCurrent(last)
    }
    tabsDidChange()
  }

  func tabsDidChange() {
    tabIndex.setTabs(browsers.filter { !$0.isIncognito }.flatMap(\.tabStates))
    incognitoTabIndex.setTabs(
      browsers.filter(\.isIncognito).flatMap(\.tabStates))
    updateControls()
  }

  /// Adds made-up pins, or unpins from the end, until there are `count`.
  private func setPinCount(_ count: Int) {
    while pins.pins.count < count {
      let url = MockBrowser.sampleURLs(count: pins.pins.count + 6).last!
      pins.add(url: url, title: URL(string: url)?.host() ?? url)
    }
    while pins.pins.count > max(count, 0), let pin = pins.pins.last {
      pins.remove(pin.id)
    }
  }

  // MARK: Controls

  private func makeControls() -> HarnessControls {
    let controls = HarnessControls()
    controls.model.setTabCount = { [weak self] count in
      self?.currentBrowser?.setTabCount(count)
    }
    controls.model.setPinCount = { [weak self] count in
      self?.setPinCount(count)
    }
    controls.model.showLocationPrompt = { [weak self] in
      self?.currentBrowser?.showLocationPrompt()
    }
    controls.model.openTabFromLink = { [weak self] inFront in
      self?.currentBrowser?.openTabFromLink(
        MockBrowser.sampleURLs(count: 4).last!, inFront: inFront)
    }
    return controls
  }

  private func makeCurrent(_ browser: MockBrowser) {
    currentBrowser = browser
    controls.attach(to: browser.window)
    updateControls()
  }

  private func updateControls() {
    controls.update(
      tabCount: currentBrowser?.tabs.count ?? 0, pinCount: pins.pins.count)
  }

  @objc private func windowDidBecomeKey(_ notification: Notification) {
    if let browser = browsers.first(where: {
      $0.window === notification.object as? NSWindow
    }) {
      makeCurrent(browser)
    }
  }

  @objc private func showControls(_ sender: Any?) {
    controls.show()
  }

  func browser(withTab tabID: Int) -> MockBrowser? {
    browsers.first { $0.tabs.contains { $0.id == tabID } }
  }

  /// Like Chrome, switching to a tab in another window brings it forward.
  func selectTab(withID tabID: Int) {
    browser(withTab: tabID)?.show(tabWithID: tabID)
  }

  @objc private func newWindow(_ sender: Any?) {
    openWindow(urls: [MockBrowser.homeURL])
  }

  @objc private func newIncognitoWindow(_ sender: Any?) {
    openWindow(urls: [MockBrowser.newTabURL], isIncognito: true)
  }

  @objc private func switchProfile(_ sender: Any?) {
    showSwitcher(page: .profiles)
  }

  @objc private func addProfile(_ sender: Any?) {
    showSwitcher(page: .newProfile)
  }

  private func showSwitcher(page: FiberProfileSwitcherPage) {
    guard let window = NSApp.keyWindow ?? browsers.last?.window else {
      return
    }
    profiles.showSwitcher(in: window, page: page)
  }

  private func makeMainMenu() -> NSMenu {
    let main = NSMenu()
    func submenu(_ title: String, _ items: [NSMenuItem]) {
      let menu = NSMenu(title: title)
      items.forEach(menu.addItem)
      main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu =
        menu
    }
    func item(_ title: String, _ action: Selector?, _ key: String = "")
      -> NSMenuItem
    {
      NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    submenu(
      "FiberUIHarness",
      [item("Quit", #selector(NSApplication.terminate(_:)), "q")])
    let newWindow = item("New Window", #selector(newWindow(_:)), "n")
    newWindow.target = self
    let newIncognitoWindow = item(
      "New Incognito Window", #selector(newIncognitoWindow(_:)), "N")
    newIncognitoWindow.target = self
    submenu(
      "File",
      [
        newWindow,
        newIncognitoWindow,
        item("New Tab", #selector(MockBrowser.newTab(_:)), "t"),
        item("Open Location…", #selector(MockBrowser.openLocation(_:)), "l"),
        .separator(),
        item("Close Window", #selector(NSWindow.performClose(_:)), "W"),
        item("Close Tab", #selector(MockBrowser.closeTab(_:)), "w"),
      ])
    submenu(
      "Edit",
      [
        item("Undo", Selector(("undo:")), "z"),
        item("Redo", Selector(("redo:")), "Z"),
        .separator(),
        item("Cut", #selector(NSText.cut(_:)), "x"),
        item("Copy", #selector(NSText.copy(_:)), "c"),
        item("Paste", #selector(NSText.paste(_:)), "v"),
        item("Select All", #selector(NSText.selectAll(_:)), "a"),
        .separator(),
        // Like Chrome's Find submenu, handled by the key window's MockBrowser.
        item("Find…", #selector(MockBrowser.findInPage(_:)), "f"),
        item("Find Next", #selector(MockBrowser.findNextInPage(_:)), "g"),
        item(
          "Find Previous", #selector(MockBrowser.findPreviousInPage(_:)), "G"),
      ])
    let showControls = item(
      "Harness Controls", #selector(showControls(_:)), "H")
    showControls.target = self
    // Handled by the key window's MockBrowser, which the window forwards
    // menu actions to (like Chrome's main menu commands in the real app).
    submenu(
      "View",
      [
        // Handled by the window itself, as in the real app.
        item("Show Tabs", #selector(NSWindow.toggleToolbarShown(_:)), "s"),
        item(
          "Command Palette",
          #selector(FiberWindowMenuActions.toggleCommandPalette(_:)), "p"),
        item(
          "Key Passthrough",
          #selector(FiberWindowMenuActions.toggleKeyPassthrough(_:))),
        item("Reload Page", #selector(MockBrowser.reloadPage(_:)), "r"),
        item("Simulate Swipe Back", #selector(MockBrowser.simulateSwipeBack(_:)), "["),
        item(
          "Simulate Swipe Forward", #selector(MockBrowser.simulateSwipeForward(_:)),
          "]"),
        // What a page going fullscreen does.
        item("Toggle Controls", #selector(MockBrowser.toggleControls(_:))),
        // What adding an extension from a store does.
        item(
          "Simulate Extension Install",
          #selector(MockBrowser.simulateExtensionInstall(_:)), "e"),
        // What an extension opening a window of its own does.
        item(
          "Simulate Extension Window",
          #selector(MockBrowser.simulateExtensionWindow(_:)), "E"),
        .separator(),
        showControls,
      ])
    let switchProfile = item("Switch Profile…", #selector(switchProfile(_:)), "M")
    switchProfile.target = self
    let addProfile = item("Add Profile…", #selector(addProfile(_:)))
    addProfile.target = self
    submenu("Profiles", [switchProfile, addProfile])
    return main
  }
}
