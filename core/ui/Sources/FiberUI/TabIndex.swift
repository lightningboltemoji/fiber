import AppKit
import FiberBridge

@objc @implementation extension FiberTabIndexFactory {
  class func tabIndex() -> any FiberTabIndex {
    TabIndex()
  }
}

/// A profile's tabs and the text of their pages, which the command palettes
/// of its windows search.
@MainActor
final class TabIndex: NSObject, FiberTabIndex {
  enum Change {
    case tabs
    case pageText
  }

  private(set) var tabs: [FiberTabState] = []
  let pageText = PageTextIndex()
  private var observers: [ObjectIdentifier: (Change) -> Void] = [:]
  /// Each tab's names, split up for matching, as of its title and URL.
  private var candidates:
    [Int: (title: String, url: String, candidate: MatchCandidate)] = [:]

  func setTabs(_ tabs: [FiberTabState]) {
    self.tabs = tabs
    let tabIDs = Set(tabs.map(\.tabID))
    candidates = candidates.filter { tabIDs.contains($0.key) }
    pageText.keepTabs(tabIDs)
    notify(.tabs)
  }

  func setPageText(_ text: String, forTabWithID tabID: Int) {
    guard tabs.contains(where: { $0.tabID == tabID }) else {
      return
    }
    pageText.setText(text, forTab: tabID)
    notify(.pageText)
  }

  func candidate(for tab: FiberTabState) -> MatchCandidate {
    if let cached = candidates[tab.tabID], cached.title == tab.title,
      cached.url == tab.url
    {
      return cached.candidate
    }
    let candidate = MatchCandidate.tab(title: tab.title, url: tab.url)
    candidates[tab.tabID] = (tab.title, tab.url, candidate)
    return candidate
  }

  /// Calls `onChange` when the tabs or their text change, until
  /// `removeObserver(_:)`.
  func addObserver(_ observer: AnyObject, onChange: @escaping (Change) -> Void)
  {
    observers[ObjectIdentifier(observer)] = onChange
  }

  func removeObserver(_ observer: AnyObject) {
    observers[ObjectIdentifier(observer)] = nil
  }

  private func notify(_ change: Change) {
    for onChange in observers.values {
      onChange(change)
    }
  }
}
