import Foundation
import FiberBridge

/// Plays //fiber/browser's TabIndexSource for the windows the command palette
/// can bring back: those closed (Chrome's recently closed) and earlier
/// sessions, which `--restorables N` makes up, with N closed windows.
@MainActor
final class MockRestorables {
  struct Tab {
    let url: String
    let title: String
  }

  struct Restorable {
    let id: String
    let kind: FiberRestorableKind
    let date: Date
    /// Each window's tabs.
    let windows: [[Tab]]

    /// Its tabs that the index lists: all but New Tab pages.
    @MainActor var listed: [Tab] {
      windows.joined().filter { $0.url != MockBrowser.newTabURL }
    }
  }

  /// Newest first.
  private var closedWindows: [Restorable] = []
  private var sessions: [Restorable] = []
  private var lastID = 0

  func windowClosed(tabs: [Tab]) {
    lastID += 1
    closedWindows.insert(
      Restorable(
        id: "window:\(lastID)", kind: .window, date: Date(), windows: [tabs]),
      at: 0)
  }

  /// `count` made-up closed windows, an hour apart, and sessions, a day apart,
  /// sharing some of their pages.
  func addSamples(_ count: Int) {
    let urls = Array(MockBrowser.sampleURLs(count: 20).dropFirst())
    func tabs(_ n: Int) -> [Tab] {
      (0..<(2 + n)).map { urls[(n * 5 + $0) % urls.count] }
        .map { Tab(url: $0, title: MockPageView.title(for: $0)) }
    }
    for n in 0..<count {
      lastID += 1
      closedWindows.append(
        Restorable(
          id: "window:\(lastID)", kind: .window,
          date: Date(timeIntervalSinceNow: -Double(n + 1) * 3600),
          windows: [tabs(n)]))
      sessions.append(
        Restorable(
          id: "session:\(n)", kind: .session,
          date: Date(timeIntervalSinceNow: -Double(n + 1) * 86400),
          windows: (0...(n % 2)).map { tabs(n + $0) }))
    }
  }

  /// As the index gets them, newest first: sessions only while some page of
  /// theirs isn't open (`openURLs`).
  func states(openURLs: Set<String>) -> [FiberRestorable] {
    (closedWindows + sessions.filter {
      !Set($0.listed.map(\.url)).isSubset(of: openURLs)
    })
    .filter { !$0.listed.isEmpty }
    .sorted { $0.date > $1.date }
    .map {
      FiberRestorable(
        id: $0.id, kind: $0.kind, date: $0.date,
        windowCount: $0.windows.count,
        pages: $0.listed.map {
          FiberRestorablePage(
            title: $0.title, url: MockBrowser.displayURL($0.url))
        })
    }
  }

  /// What `id` names: a closed window leaves the list, as Chrome's restoring
  /// it does, but a session stays.
  func take(_ id: String) -> Restorable? {
    if let index = closedWindows.firstIndex(where: { $0.id == id }) {
      return closedWindows.remove(at: index)
    }
    return sessions.first { $0.id == id }
  }
}
