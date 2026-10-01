import AppKit
import FiberBridge

/// Plays Chrome's find in page for a window's find bar: a session per tab,
/// counting matches in the made-up page's text (MockPages), and one query for
/// them all, as macOS's find pasteboard makes it.
@MainActor
final class MockFindBar: NSObject, FiberFindBarActions {
  private let ui: any FiberFindBar
  private let focusPage: () -> Void
  private var tab: MockTab
  /// The tabs whose bar is open.
  private var sessions: Set<Int> = []
  private var query = ""
  private var activeMatch = 0

  init(ui: any FiberFindBar, tab: MockTab, focusPage: @escaping () -> Void) {
    self.ui = ui
    self.tab = tab
    self.focusPage = focusPage
    super.init()
    ui.actions = self
  }

  /// Command-F, or with `findNext`, Command-G and Shift-Command-G.
  func open(findNext: Bool = false, forward: Bool = true) {
    sessions.insert(tab.id)
    ui.show(animated: true, focus: true)
    ui.focusAndSelectAll()
    if findNext {
      step(forward: forward)
    } else {
      // Counts without moving to a match, as Chrome does.
      activeMatch = 0
      report()
    }
  }

  func tabDidActivate(_ tab: MockTab) {
    self.tab = tab
    activeMatch = 0
    if sessions.contains(tab.id) {
      ui.show(animated: false, focus: false)
      report()
    } else {
      ui.hide(animated: false)
    }
  }

  /// Leaving the page ends its tab's session.
  func pageWillChange(in tab: MockTab) {
    if tab === self.tab {
      close()
    } else {
      sessions.remove(tab.id)
    }
  }

  private func close() {
    sessions.remove(tab.id)
    if ui.hasFocus {
      focusPage()
    }
    ui.hide(animated: true)
  }

  private var matchCount: Int {
    guard !query.isEmpty else {
      return -1
    }
    let text = (MockPages.page(for: tab.url)?.text ?? "").lowercased()
    return text.ranges(of: query.lowercased()).count
  }

  private func step(forward: Bool) {
    let count = matchCount
    guard count > 0 else {
      report()
      return
    }
    activeMatch =
      forward
      ? activeMatch % count + 1 : (activeMatch <= 1 ? count : activeMatch - 1)
    report()
  }

  private func report() {
    ui.setMatchCount(matchCount, activeMatch: activeMatch)
  }

  // MARK: FiberFindBarActions

  func findBarTextDidChange(_ text: String) {
    query = text
    activeMatch = matchCount > 0 ? 1 : 0
    report()
  }

  func findBarFindNext() {
    step(forward: true)
  }

  func findBarFindPrevious() {
    step(forward: false)
  }

  func findBarClose() {
    close()
  }

  func findBarFocusDidChange(_ focused: Bool) {}
}
