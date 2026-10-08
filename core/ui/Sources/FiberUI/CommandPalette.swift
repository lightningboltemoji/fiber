import AppKit
import FiberBridge

/// A browser command the command palette lists.
enum PaletteCommand: CaseIterable, Hashable {
  case newTab
  case print
  case keyPassthrough

  var command: FiberCommand {
    switch self {
    case .newTab: .newTab
    case .print: .print
    case .keyPassthrough: .keyPassthrough
    }
  }

  var title: String {
    switch self {
    case .newTab: "New Tab"
    case .print: "Print…"
    case .keyPassthrough: "Key Passthrough"
    }
  }

  /// Other words for it, which find it too.
  var aliases: [String] {
    switch self {
    case .newTab: ["Open Tab"]
    case .print: ["PDF", "Save as PDF"]
    case .keyPassthrough: ["Pass Keys to Page", "Keyboard Shortcuts"]
    }
  }

  var symbolName: String {
    switch self {
    case .newTab: "plus.square.on.square"
    case .print: "printer"
    case .keyPassthrough: "keyboard"
    }
  }

  /// Its key equivalent in the main menu, if any.
  var shortcut: String {
    switch self {
    case .newTab: "⌘T"
    case .print: "⌥⌘P"
    case .keyPassthrough: ""
    }
  }

  var candidate: MatchCandidate {
    .command(title: title, aliases: aliases)
  }
}

/// A row of the command palette.
struct PaletteItem: Equatable {
  enum Kind: Hashable {
    case tab(Int)
    /// A tab listed for what's in its page.
    case pageText(Int)
    case command(PaletteCommand)
    /// A closed window or earlier session, by the page of it that matched or
    /// as a whole.
    case restorable(String, page: Int?)
  }

  let kind: Kind
  var title: String
  var titleRanges: [NSRange] = []
  var subtitle = ""
  var subtitleRanges: [NSRange] = []
  /// For page text: the words around the match.
  var snippet = ""
  var snippetRanges: [NSRange] = []
  var favicon: NSImage?
  /// For a command, in place of a favicon.
  var symbolName: String?
  /// On its right, like "Current tab", or a command's shortcut.
  var accessory = ""
  /// For page text: what finds the match in the page.
  var findText = ""
}

/// Fiber's command palette (Command-P): the profile's tabs, in all its
/// windows, browser commands, and the windows it can bring back, found by name
/// or by what's in the tabs' pages. Before the user types, the tabs, most
/// recently used first. Covers the window while open. See .agents/PALETTE.md.
@MainActor
final class CommandPalette: NSObject {
  private static let pageStep = 5

  let view = PaletteView(placeholder: "Search tabs and commands")
  var onOpen: () -> Void = {}
  /// Called when the palette is done: the user picked something, pressed
  /// Escape, or clicked outside it. Its owner closes it.
  var onDismiss: () -> Void = {} {
    didSet { view.onDismiss = onDismiss }
  }
  var isOpen: Bool { view.isOpen }

  private let index: TabIndex
  private let actions: any FiberWindowActions
  private let list = PaletteResultList()
  private var field: NSTextField { view.field }
  /// The window's own tabs, and the one it shows.
  private var windowTabIDs: Set<Int> = []
  private var activeTabID: Int?
  /// The commands that can run, as of opening.
  private var commands: [PaletteCommand] = []
  private var queryText = ""
  private var query = PaletteQuery("")
  private var nameItems: [PaletteItem] = []
  private var pageTextCandidates: [Int: PaletteSearch.PageTextCandidate] = [:]
  private var pageTextMatches: [PageTextMatch] = []
  private var items: [PaletteItem] = []
  private var selectedIndex = 0
  /// Page text is searched one query at a time; a newer one waits.
  private var isSearchingPageText = false
  private var needsPageTextSearch = false

  init(index: TabIndex, actions: any FiberWindowActions) {
    self.index = index
    self.actions = actions
    super.init()
    field.target = self
    field.action = #selector(submit(_:))
    field.delegate = self
    list.onOpen = { [weak self] index in self?.open(at: index) }
    view.list = list
  }

  /// The window's tabs, which the palette marks, and the one it shows.
  func setWindowTabs(_ tabs: [FiberTabState], activeTabID: Int) {
    windowTabIDs = Set(tabs.map(\.tabID))
    self.activeTabID = activeTabID
    if isOpen {
      refresh(keepingSelection: true, searchingPageText: false)
    }
  }

  /// Opens the palette, empty. If it's open, its text is selected.
  func open() {
    guard !isOpen else {
      field.currentEditor()?.selectAll(nil)
      return
    }
    commands = PaletteCommand.allCases.filter {
      actions.canRun($0.command)
    }
    field.stringValue = ""
    queryText = ""
    query = PaletteQuery("")
    pageTextMatches = []
    index.addObserver(self) { [weak self] change in
      self?.refresh(
        keepingSelection: true, searchingPageText: change == .pageText)
    }
    refresh(keepingSelection: false, searchingPageText: false)
    onOpen()
    view.open()
    actions.commandPaletteDidOpen()
  }

  func close() {
    guard isOpen else {
      return
    }
    index.removeObserver(self)
    view.close()
  }

  // MARK: Searching

  private func queryDidChange() {
    guard field.stringValue != queryText else {
      return
    }
    queryText = field.stringValue
    query = PaletteQuery(queryText)
    pageTextMatches = []
    refresh(keepingSelection: false, searchingPageText: true)
  }

  /// Ranks the tabs and commands by name, and looks for the query in the
  /// pages of the tabs whose names don't match all of it.
  private func refresh(keepingSelection: Bool, searchingPageText: Bool) {
    let tabs = index.tabs
    var entries = tabs.map { tab in
      PaletteSearch.Entry(
        id: .tab(tab.tabID), candidate: index.candidate(for: tab),
        lastActive: tab.lastActiveTime, isCurrent: tab.tabID == activeTabID)
    }
    if !query.isEmpty {
      entries += commands.map {
        PaletteSearch.Entry(
          id: .command($0), candidate: $0.candidate, lastActive: nil,
          isCurrent: false)
      }
      entries += restorableEntries(openURLs: Set(tabs.map(\.url)))
    }
    let ranked = PaletteSearch.rank(query, entries: entries)
    let tabsByID = Dictionary(
      tabs.map { ($0.tabID, $0) }, uniquingKeysWith: { first, _ in first })
    // Each restorable once, by its best match, and each page once, in the
    // most recent that has it, which ranks first.
    var listedRestorables: Set<String> = []
    var listedPages: Set<String> = []
    nameItems = ranked.results.compactMap { result in
      switch result.id {
      case .tab(let tabID):
        tabsByID[tabID].map {
          tabItem(
            .tab(tabID), tab: $0, titleRanges: result.titleRanges,
            subtitleRanges: result.subtitleRanges)
        }
      case .command(let command):
        PaletteItem(
          kind: .command(command), title: command.title,
          titleRanges: result.titleRanges, symbolName: command.symbolName,
          accessory: command.shortcut)
      case .restorable(let id, let page):
        restorableItem(
          id: id, page: page, result: result, listed: &listedRestorables,
          listedPages: &listedPages)
      }
    }
    pageTextCandidates = Dictionary(
      ranked.pageText.map { ($0.tabID, $0) },
      uniquingKeysWith: { first, _ in first })
    // Tabs that match by name now, or are gone, aren't listed for their text.
    pageTextMatches.removeAll { pageTextCandidates[$0.tabID] == nil }
    show(keepingSelection: keepingSelection, tabs: tabsByID)
    if searchingPageText {
      searchPageText()
    }
  }

  private func searchPageText() {
    guard query.searchesPageText, !pageTextCandidates.isEmpty else {
      return
    }
    if isSearchingPageText {
      needsPageTextSearch = true
      return
    }
    isSearchingPageText = true
    let searchedText = queryText
    index.pageText.search(query, in: Array(pageTextCandidates.values)) {
      [weak self] matches in
      guard let self else {
        return
      }
      self.isSearchingPageText = false
      if self.needsPageTextSearch {
        self.needsPageTextSearch = false
        self.searchPageText()
      }
      guard self.isOpen else {
        return
      }
      // Unless a newer search is on its way.
      if !self.isSearchingPageText, searchedText == self.queryText {
        self.pageTextMatches = matches.filter {
          self.pageTextCandidates[$0.tabID] != nil
        }
      }
      self.show(
        keepingSelection: true,
        tabs: Dictionary(
          self.index.tabs.map { ($0.tabID, $0) },
          uniquingKeysWith: { first, _ in first }))
    }
  }

  // MARK: The list

  private func show(keepingSelection: Bool, tabs: [Int: FiberTabState]) {
    let selected =
      keepingSelection && items.indices.contains(selectedIndex)
      ? items[selectedIndex].kind : nil
    let pageItems = pageTextMatches.compactMap { match -> PaletteItem? in
      guard let tab = tabs[match.tabID] else {
        return nil
      }
      let candidate = pageTextCandidates[match.tabID]
      var item = tabItem(
        .pageText(match.tabID), tab: tab,
        titleRanges: candidate?.titleRanges ?? [],
        subtitleRanges: candidate?.subtitleRanges ?? [])
      item.snippet = match.snippet
      item.snippetRanges = match.snippetRanges
      item.findText = match.findText
      return item
    }
    items = nameItems + pageItems
    let isSearching = isSearchingPageText || needsPageTextSearch
    list.setItems(
      items, pageTextStart: pageItems.isEmpty ? nil : nameItems.count,
      message: items.isEmpty && !query.isEmpty && !isSearching
        ? "No tabs or commands match" : nil)
    view.listContentHeight = list.contentHeight
    if let selected,
      let index = items.firstIndex(where: { $0.kind == selected })
    {
      select(index)
    } else if query.isEmpty, items.count > 1,
      items[0].kind == .tab(activeTabID ?? -1)
    {
      // Return goes back to the tab used before this one.
      select(1)
    } else {
      select(0)
    }
  }

  /// The windows the palette can bring back, by each of their pages but those
  /// open now (the open tab is the one wanted), and by what they are.
  private func restorableEntries(openURLs: Set<String>)
    -> [PaletteSearch.Entry]
  {
    index.restorables.flatMap { restorable in
      let pages = restorable.pages.indices.filter {
        !openURLs.contains(restorable.pages[$0].url)
      }
      return (pages.map(Optional.some) + [nil]).map { page in
        PaletteSearch.Entry(
          id: .restorable(restorable.restorableID, page: page),
          candidate: index.candidate(for: restorable, page: page),
          lastActive: restorable.date, isCurrent: false)
      }
    }
  }

  private func restorable(withID id: String) -> FiberRestorable? {
    index.restorables.first { $0.restorableID == id }
  }

  /// One of the restorable's pages, if that's what matched; otherwise the
  /// restorable, named by its pages. Nil if either is listed already.
  private func restorableItem(
    id: String, page: Int?, result: PaletteSearch.Result,
    listed: inout Set<String>, listedPages: inout Set<String>
  ) -> PaletteItem? {
    guard !listed.contains(id), let restorable = restorable(withID: id) else {
      return nil
    }
    let isWindow = restorable.kind == .window
    let symbolName = isWindow ? "macwindow" : "clock.arrow.circlepath"
    if let page, !result.titleRanges.isEmpty || !result.subtitleRanges.isEmpty
    {
      let shown = restorable.pages[page]
      guard listedPages.insert(shown.url).inserted else {
        return nil
      }
      listed.insert(id)
      return PaletteItem(
        kind: .restorable(restorable.restorableID, page: page),
        title: shown.title, titleRanges: result.titleRanges,
        subtitle: shown.url, subtitleRanges: result.subtitleRanges,
        symbolName: symbolName,
        accessory: isWindow ? "Closed window" : "Earlier session")
    }
    listed.insert(id)
    let titles = restorable.pages.map(\.title)
    let named = titles.prefix(3).joined(separator: ", ")
    let tabs = Self.count(restorable.pages.count, "tab")
    let windows = Self.count(restorable.windowCount, "window")
    return PaletteItem(
      kind: .restorable(restorable.restorableID, page: nil),
      title: titles.count > 3 ? "\(named) and \(titles.count - 3) more" : named,
      subtitle: isWindow
        ? "Closed window · \(tabs)" : "Earlier session · \(windows) · \(tabs)",
      symbolName: symbolName,
      accessory: Self.when(restorable))
  }

  private static func count(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
  }

  /// When a window closed ("2 hours ago"), or a session ended ("Yesterday at
  /// 6:40 PM", as History › Previous Sessions has it).
  private static func when(_ restorable: FiberRestorable) -> String {
    restorable.kind == .window
      ? restorable.date.formatted(.relative(presentation: .named))
      : sessionDateFormatter.string(from: restorable.date)
  }

  private static let sessionDateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
  }()

  private func tabItem(
    _ kind: PaletteItem.Kind, tab: FiberTabState, titleRanges: [NSRange],
    subtitleRanges: [NSRange]
  ) -> PaletteItem {
    PaletteItem(
      kind: kind, title: tab.title.isEmpty ? "Untitled" : tab.title,
      titleRanges: tab.title.isEmpty ? [] : titleRanges, subtitle: tab.url,
      subtitleRanges: subtitleRanges, favicon: tab.favicon,
      accessory: tab.tabID == activeTabID
        ? "Current tab"
        : windowTabIDs.contains(tab.tabID) ? "" : "Other window")
  }

  private func select(_ index: Int) {
    selectedIndex = items.isEmpty ? 0 : min(max(index, 0), items.count - 1)
    list.setSelection(items.isEmpty ? nil : selectedIndex)
    let action: String? =
      switch items.isEmpty ? nil : items[selectedIndex].kind {
      case .tab: "Switch to Tab"
      case .pageText: "Show in Page"
      case .command: "Run"
      case .restorable(let id, _):
        restorable(withID: id).map {
          $0.windowCount == 1
            ? "Reopen Window" : "Reopen \($0.windowCount) Windows"
        }
      case nil: nil
      }
    view.hints = (action.map { [($0, "↩")] } ?? []) + [("Close", "esc")]
  }

  @objc private func submit(_ sender: Any?) {
    open(at: selectedIndex)
  }

  private func open(at index: Int) {
    guard items.indices.contains(index) else {
      return
    }
    let item = items[index]
    onDismiss()
    switch item.kind {
    case .tab(let tabID):
      actions.selectTab(withID: tabID)
    case .pageText(let tabID):
      actions.revealText(item.findText, inTabWithID: tabID)
    case .command(let command):
      actions.run(command.command)
    case .restorable(let id, let page):
      actions.restore(id, showingPageAt: page ?? NSNotFound)
    }
  }
}

extension CommandPalette: NSTextFieldDelegate {
  func controlTextDidChange(_ notification: Notification) {
    queryDidChange()
  }

  func control(
    _ control: NSControl, textView: NSTextView,
    doCommandBy selector: Selector
  ) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)):
      onDismiss()
    case #selector(NSResponder.moveUp(_:)),
      #selector(NSResponder.insertBacktab(_:)):
      select(selectedIndex - 1)
    case #selector(NSResponder.moveDown(_:)),
      #selector(NSResponder.insertTab(_:)):
      select(selectedIndex + 1)
    case #selector(NSResponder.pageUp(_:)),
      #selector(NSResponder.scrollPageUp(_:)):
      select(selectedIndex - Self.pageStep)
    case #selector(NSResponder.pageDown(_:)),
      #selector(NSResponder.scrollPageDown(_:)):
      select(selectedIndex + Self.pageStep)
    // Return with modifiers, which the field would otherwise take as a line
    // break (Option-Return) or beep at (Command-Return).
    case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
      Selector(("noop:")):
      guard PaletteView.isReturn(NSApp.currentEvent) else {
        return false
      }
      submit(nil)
    default:
      return false
    }
    return true
  }
}
