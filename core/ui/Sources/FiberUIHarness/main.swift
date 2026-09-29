// Runs Fiber's UI against a mock browser that uses the bridge exactly as
// //fiber/browser does, without Chromium. Flags: `--tabs N` (made-up sites),
// `--downloads N` (which quitting waits for), `--ask-before-leaving`,
// `--palette QUERY` (the command palette, open with QUERY typed),
// `--extension-window` (a window an extension opened, as its bubble).

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
  /// Every window's tabs, as one profile's.
  let tabIndex = FiberTabIndexFactory.tabIndex()
  private lazy var downloads = MockDownloads(count: launchDownloadCount)
  /// Set once the downloads are done, so the quit they held up goes ahead.
  private var isDoneWaiting = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()
    openWindow(urls: MockBrowser.sampleURLs(count: launchTabCount))
    NSApp.activate()
    if CommandLine.arguments.contains("--extension-window") {
      browsers.last?.simulateExtensionWindow(nil)
    }
    if let query = launchPaletteQuery {
      // Once the pages have loaded, so there's text to find.
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        MainActor.assumeIsolated {
          self?.browsers.last?.openCommandPalette(typing: query)
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

  private var launchPaletteQuery: String? {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--palette"),
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

  func openWindow(urls: [String]) {
    let browser = MockBrowser(urls: urls, app: self)
    browsers.append(browser)
    tabsDidChange()
    browser.show()
  }

  func browserDidClose(_ browser: MockBrowser) {
    browsers.removeAll { $0 === browser }
    tabsDidChange()
  }

  func tabsDidChange() {
    tabIndex.setTabs(browsers.flatMap(\.tabStates))
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
    submenu(
      "File",
      [
        newWindow,
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
      ])
    // Handled by the key window's MockBrowser, which the window forwards
    // menu actions to (like Chrome's main menu commands in the real app).
    submenu(
      "View",
      [
        // Handled by the window itself, as in the real app.
        item("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "s"),
        item(
          "Command Palette",
          #selector(FiberWindowMenuActions.toggleCommandPalette(_:)), "p"),
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
      ])
    return main
  }
}
