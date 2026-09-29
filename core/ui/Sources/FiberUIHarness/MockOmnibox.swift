import AppKit
import FiberBridge

/// Plays Chrome's omnibox for the harness's omnibar: enough to exercise the
/// omnibar, not a model of Chrome's ranking.
@MainActor
final class MockOmnibox: NSObject, FiberOmniboxActions {
  private struct Entry {
    var kind: FiberSuggestionKind
    var contents: String
    var detail = ""
    /// What the field shows while it's selected, and what opening it opens.
    var fill: String
    var header = ""
    var keywordLabel = ""
    var actionTitles: [String] = []
    var removable = false

    /// Its parts, in the order Tab steps through them.
    var parts: [(FiberSuggestionPart, Int)] {
      [(.row, 0)] + (keywordLabel.isEmpty ? [] : [(.keyword, 0)])
        + actionTitles.indices.map { (.action, $0) }
        + (removable ? [(.remove, 0)] : [])
    }
  }

  private static let recentSearches = ["liquid glass", "chromium release notes"]

  private let ui: any FiberOmnibox
  /// The page's URL, which the field starts with.
  private let currentURL: () -> String
  /// Opens a URL or search, with the event whose modifiers say where.
  private let open: (String, NSEvent?) -> Void

  private var userText = ""
  private var inlineCompletion = ""
  private var keyword = ""
  private var entries: [Entry] = []
  private var removed: Set<String> = []
  private var selected = -1
  private var selectedPart = 0

  init(
    ui: any FiberOmnibox, currentURL: @escaping () -> String,
    open: @escaping (String, NSEvent?) -> Void
  ) {
    self.ui = ui
    self.currentURL = currentURL
    self.open = open
  }

  // MARK: FiberOmniboxActions

  func omniboxDidFocus() {
    let url = currentURL()
    userText = url
    inlineCompletion = ""
    ui.setText(url, selectedRange: NSRange(location: 0, length: url.utf16.count))
    // Before the user types: recent searches, then pages.
    entries =
      Self.recentSearches.enumerated().map { index, query in
        Entry(
          kind: .searchHistory, contents: query, fill: query,
          header: index == 0 ? "Recent searches" : "", removable: true)
      }
      + MockBrowser.sampleURLs(count: 4).dropFirst().enumerated().map {
        index, url in
        Entry(
          kind: .page, contents: Self.title(for: url), detail: Self.host(url),
          fill: url, header: index == 0 ? "Recently visited" : "",
          removable: true)
      }
    entries.removeAll { removed.contains($0.fill) }
    select(-1, updateText: false)
    pushSuggestions()
  }

  func omniboxDidBlur() {
    keyword = ""
    entries = []
    ui.setKeywordLabel("")
    ui.setSuggestions([])
  }

  func omniboxTextDidChange(
    _ text: String, selectedRange: NSRange, composing: Bool
  ) {
    let length = text.utf16.count
    let caretAtEnd = selectedRange.location == length
    if text == userText + inlineCompletion {
      // Only the selection moved, which accepts the inline completion.
      if !inlineCompletion.isEmpty,
        selectedRange != NSRange(
          location: userText.utf16.count, length: inlineCompletion.utf16.count)
      {
        userText = text
        inlineCompletion = ""
      }
      return
    }
    let deleted = text.utf16.count < userText.utf16.count
    userText = text
    query(autocomplete: caretAtEnd && !deleted && !composing)
  }

  func omniboxMoveSelection(_ move: FiberSuggestionMove) {
    guard !entries.isEmpty else {
      return
    }
    switch move {
    case .up:
      select(max(selected - 1, -1))
    case .down:
      select(min(selected + 1, entries.count - 1))
    case .pageUp:
      select(0)
    case .pageDown:
      select(entries.count - 1)
    case .next, .previous:
      stepPart(forward: move == .next)
    @unknown default:
      break
    }
  }

  func omniboxOpenSelection(with event: NSEvent?) {
    if selected >= 0 {
      openEntry(selected, part: entries[selected].parts[selectedPart].0,
        event: event)
    } else {
      open(userText + inlineCompletion, event)
    }
  }

  func omniboxOpenSuggestion(
    at index: Int, part: FiberSuggestionPart, actionIndex: Int, event: NSEvent?
  ) {
    guard entries.indices.contains(index) else {
      return
    }
    openEntry(index, part: part, event: event)
  }

  func omniboxRemoveSuggestion(at index: Int) {
    guard entries.indices.contains(index), entries[index].removable else {
      return
    }
    removed.insert(entries[index].fill)
    entries.remove(at: index)
    select(min(selected, entries.count - 1))
    pushSuggestions()
  }

  func omniboxClearKeyword() {
    keyword = ""
    ui.setKeywordLabel("")
    query(autocomplete: false)
  }

  // MARK: Private

  private func query(autocomplete: Bool) {
    let typed = userText.trimmingCharacters(in: .whitespaces)
    inlineCompletion = ""
    entries = []
    guard !typed.isEmpty else {
      ui.setText(userText, selectedRange: caret(at: userText))
      pushSuggestions()
      return
    }
    if !keyword.isEmpty {
      entries = [
        Entry(kind: .search, contents: typed, detail: keyword, fill: typed)
      ]
      select(0)
      pushSuggestions()
      return
    }
    let sites = MockBrowser.sampleURLs(count: 20).filter {
      !removed.contains($0)
        && (Self.host($0).hasPrefix(typed.lowercased())
          || Self.title(for: $0).localizedCaseInsensitiveContains(typed))
    }
    if autocomplete,
      let site = sites.first(where: { Self.host($0).hasPrefix(typed.lowercased()) })
    {
      inlineCompletion = String(Self.host(site).dropFirst(typed.count))
    }
    let search = Entry(
      kind: .search, contents: typed, detail: "Search", fill: typed)
    let pages = sites.prefix(4).enumerated().map { index, url in
      Entry(
        kind: index == 2 ? .bookmark : .page,
        contents: Self.title(for: url), detail: Self.host(url), fill: url,
        keywordLabel: Self.host(url).hasPrefix("wiki") ? "Search Wiki" : "",
        actionTitles: index == 0 ? ["Switch to this tab"] : [],
        removable: true)
    }
    let searches = ["\(typed) news", "\(typed) near me"].map {
      Entry(kind: .search, contents: $0, fill: $0)
    }
    entries =
      (inlineCompletion.isEmpty
        ? [search] + pages : Array(pages.prefix(1)) + [search] + pages.dropFirst())
      + searches
    let text = userText + inlineCompletion
    ui.setText(
      text,
      selectedRange: NSRange(
        location: userText.utf16.count, length: inlineCompletion.utf16.count))
    select(0, updateText: false)
    pushSuggestions()
  }

  private func openEntry(_ index: Int, part: FiberSuggestionPart, event: NSEvent?) {
    let entry = entries[index]
    switch part {
    case .keyword:
      keyword = entry.keywordLabel
      userText = ""
      inlineCompletion = ""
      entries = []
      ui.setKeywordLabel(keyword)
      ui.setText("", selectedRange: NSRange(location: 0, length: 0))
      pushSuggestions()
    case .remove:
      omniboxRemoveSuggestion(at: index)
    default:
      open(entry.fill, event)
    }
  }

  /// Selects entry `index`, or what's typed for -1, putting its text in the
  /// field, as Chrome does while arrowing through suggestions.
  private func select(_ index: Int, updateText: Bool = true) {
    selected = index
    selectedPart = 0
    if updateText {
      let text =
        index >= 0 ? entries[index].fill : userText + inlineCompletion
      ui.setText(
        text,
        selectedRange: index >= 0
          ? caret(at: text)
          : NSRange(
            location: userText.utf16.count,
            length: inlineCompletion.utf16.count))
    }
    pushSelection()
  }

  private func stepPart(forward: Bool) {
    guard selected >= 0 else {
      select(forward ? 0 : entries.count - 1)
      return
    }
    let parts = entries[selected].parts
    let next = selectedPart + (forward ? 1 : -1)
    if parts.indices.contains(next) {
      selectedPart = next
      pushSelection()
    } else {
      let line = selected + (forward ? 1 : -1)
      guard entries.indices.contains(line) else {
        return
      }
      select(line)
      if !forward {
        selectedPart = entries[line].parts.count - 1
        pushSelection()
      }
    }
  }

  private func pushSuggestions() {
    ui.setSuggestions(
      entries.map { entry in
        FiberSuggestion(
          kind: entry.kind, contents: entry.contents,
          contentsRuns: Self.runs(entry.contents, matching: userText),
          detail: entry.detail,
          detailRuns: Self.runs(entry.detail, matching: userText),
          favicon: nil, header: entry.header, keywordLabel: entry.keywordLabel,
          actionTitles: entry.actionTitles, removable: entry.removable,
          hidden: false)
      })
    pushSelection()
  }

  private func pushSelection() {
    guard selected >= 0, entries.indices.contains(selected) else {
      ui.setSelectedSuggestionIndex(-1, part: .row, actionIndex: 0)
      return
    }
    let (part, actionIndex) = entries[selected].parts[selectedPart]
    ui.setSelectedSuggestionIndex(selected, part: part, actionIndex: actionIndex)
  }

  private func caret(at text: String) -> NSRange {
    NSRange(location: text.utf16.count, length: 0)
  }

  /// Marks where `text` contains what's typed, as Chrome's classifications do.
  private static func runs(_ text: String, matching typed: String)
    -> [FiberTextRun]
  {
    let string = text as NSString
    let match =
      typed.isEmpty
      ? NSRange(location: NSNotFound, length: 0)
      : string.range(of: typed, options: .caseInsensitive)
    guard match.location != NSNotFound else {
      return [
        FiberTextRun(
          range: NSRange(location: 0, length: string.length), style: [])
      ]
    }
    return [
      NSRange(location: 0, length: match.location), match,
      NSRange(
        location: NSMaxRange(match), length: string.length - NSMaxRange(match)),
    ].enumerated().compactMap { index, range in
      range.length > 0
        ? FiberTextRun(range: range, style: index == 1 ? .match : []) : nil
    }
  }

  private static func host(_ url: String) -> String {
    URL(string: url)?.host() ?? url
  }

  private static func title(for url: String) -> String {
    let host = host(url)
    let name = host.split(separator: ".").first.map(String.init) ?? host
    let path = URL(string: url)?.path() ?? ""
    return "\(name.capitalized)\(path.count > 1 ? " — \(path.dropFirst())" : "")"
  }
}
