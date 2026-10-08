import AppKit
import FiberBridge

@objc @implementation extension FiberTabIndexFactory {
  class func tabIndex() -> any FiberTabIndex {
    TabIndex()
  }
}

/// A profile's tabs and the text of their pages, which the command palettes
/// of its windows search, and the windows they can bring back.
@MainActor
final class TabIndex: NSObject, FiberTabIndex {
  enum Change {
    case tabs
    case pageText
    case restorables
  }

  private(set) var tabs: [FiberTabState] = []
  /// Most recent first.
  private(set) var restorables: [FiberRestorable] = []
  let pageText = PageTextIndex()
  private var observers: [ObjectIdentifier: (Change) -> Void] = [:]
  /// Each tab's names, split up for matching, as of its title and URL.
  private var candidates:
    [Int: (title: String, url: String, candidate: MatchCandidate)] = [:]
  /// Each restorable's pages' names, split up for matching, then its own.
  /// What an ID names doesn't change.
  private var restorableCandidates: [String: [MatchCandidate]] = [:]

  func setTabs(_ tabs: [FiberTabState]) {
    self.tabs = tabs
    let tabIDs = Set(tabs.map(\.tabID))
    candidates = candidates.filter { tabIDs.contains($0.key) }
    pageText.keepTabs(tabIDs)
    notify(.tabs)
  }

  func setRestorables(_ restorables: [FiberRestorable]) {
    self.restorables = restorables
    let ids = Set(restorables.map(\.restorableID))
    restorableCandidates = restorableCandidates.filter { ids.contains($0.key) }
    notify(.restorables)
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

  /// `restorable`'s page `page`, by its title and URL or what the restorable
  /// is; with no page, by what it is alone.
  func candidate(for restorable: FiberRestorable, page: Int?)
    -> MatchCandidate
  {
    let all =
      restorableCandidates[restorable.restorableID]
      ?? {
        let aliases = MatchCandidate.aliasFields(restorable.kind.aliases)
        let made =
          restorable.pages.map {
            MatchCandidate(
              fields: MatchCandidate.tab(title: $0.title, url: $0.url).fields
                + aliases)
          } + [MatchCandidate(fields: aliases)]
        restorableCandidates[restorable.restorableID] = made
        return made
      }()
    return all[page ?? restorable.pages.count]
  }

  /// Calls `onChange` when the tabs, their text or the restorables change,
  /// until `removeObserver(_:)`.
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

extension FiberRestorableKind {
  /// What finds a restorable of this kind, besides its pages.
  var aliases: [String] {
    switch self {
    case .window: ["Closed Window", "Reopen Window", "Recently Closed"]
    case .session: ["Previous Session", "Reopen Session", "Restore Session"]
    @unknown default: []
    }
  }
}
