// Runs Fiber's UI against a mock browser (MockBrowser), without Chromium. The
// mock uses the bridge exactly as //fiber/browser does.

import AppKit

let app = NSApplication.shared
let delegate = HarnessAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

@MainActor
final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
  private var browsers: [MockBrowser] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()
    openWindow(url: MockBrowser.homeURL)
    NSApp.activate()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication)
    -> Bool
  {
    true
  }

  func openWindow(url: String) {
    let browser = MockBrowser(url: url, app: self)
    browsers.append(browser)
    browser.show()
  }

  func browserDidClose(_ browser: MockBrowser) {
    browsers.removeAll { $0 === browser }
  }

  @objc private func newWindow(_ sender: Any?) {
    openWindow(url: MockBrowser.homeURL)
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
        item("Open Location…", #selector(MockBrowser.openLocation(_:)), "l"),
        item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
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
        item("Reload Page", #selector(MockBrowser.reloadPage(_:)), "r"),
        item("Toggle Toolbar", #selector(MockBrowser.toggleToolbar(_:)), "t"),
      ])
    return main
  }
}
