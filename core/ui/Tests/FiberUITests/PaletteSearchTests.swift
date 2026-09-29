import Foundation
import Testing

@testable import FiberUI

/// Queries and what the palette should list first for them, against a
/// realistic set of tabs. Add a case whenever the ranking gets one wrong.
@MainActor
struct PaletteSearchTests {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let currentTab = 6

  /// ID, title, URL (as Chrome displays it), and how long ago it was used.
  private static let tabs: [(Int, String, String, minutes: Double)] = [
    (1, "GitHub", "github.com", 30),
    (
      2, "rust-lang/rust: Empowering everyone to build reliable software",
      "github.com/rust-lang/rust", 5
    ),
    (3, "The New York Times - Breaking News", "nytimes.com", 120),
    (
      4, "Print CSS - MDN Web Docs",
      "developer.mozilla.org/en-US/docs/Web/CSS/Paged_Media", 1
    ),
    (
      5, "References and Borrowing - The Rust Programming Language",
      "doc.rust-lang.org/book/ch04-02-references-and-borrowing.html", 60
    ),
    (6, "Inbox (3) - Gmail", "mail.google.com/mail/u/0/#inbox", 10),
    (7, "Pull requests · fiber/fiber", "github.com/fiber/fiber/pulls", 15),
    (8, "YouTube", "youtube.com", 300),
    (9, "Settings", "chrome://settings", 600),
    (10, "Café Déjà Vu — Menu", "cafedejavu.example/menu", 240),
    (11, "日本語のページ", "example.jp/nihongo", 100),
  ]

  private static var entries: [PaletteSearch.Entry] {
    tabs.map { id, title, url, minutes in
      PaletteSearch.Entry(
        id: .tab(id), candidate: .tab(title: title, url: url),
        lastActive: now.addingTimeInterval(-minutes * 60),
        isCurrent: id == currentTab)
    }
      + PaletteCommand.allCases.map {
        PaletteSearch.Entry(
          id: .command($0), candidate: $0.candidate, lastActive: nil,
          isCurrent: false)
      }
  }

  private func rank(_ query: String) -> [PaletteSearch.Result] {
    PaletteSearch.rank(
      PaletteQuery(query), entries: Self.entries, now: Self.now
    ).results
  }

  private func first(_ query: String) -> PaletteSearch.Entry.ID? {
    rank(query).first?.id
  }

  @Test(arguments: [
    ("github", PaletteSearch.Entry.ID.tab(1)),
    // The initials of GitHub's camel case parts.
    ("gh", .tab(1)),
    ("githbu", .tab(1)),
    ("nyt", .tab(3)),
    ("new york", .tab(3)),
    ("print", .command(.print)),
    ("prnt", .command(.print)),
    ("save as pdf", .command(.print)),
    ("new tab", .command(.newTab)),
    ("rust borrow", .tab(5)),
    ("rust book", .tab(5)),
    ("pulls", .tab(7)),
    ("fiber pul", .tab(7)),
    ("cafe deja", .tab(10)),
    ("日本語", .tab(11)),
    ("settings", .tab(9)),
    ("mozilla", .tab(4)),
    ("mdn", .tab(4)),
    // The current tab, when it's the only match.
    ("gmail", .tab(6)),
  ])
  func firstResult(query: String, expected: PaletteSearch.Entry.ID) {
    #expect(first(query) == expected)
  }

  @Test func emptyQueryListsTheCurrentTabThenMostRecent() {
    #expect(
      rank("").map(\.id)
        == [6, 4, 2, 7, 1, 5, 11, 3, 10, 8, 9].map {
          .tab($0)
        })
  }

  @Test func strongMatchesListFirst() {
    let results = rank("rust")
    #expect(Set(results.prefix(2).map(\.id)) == [.tab(2), .tab(5)])
    #expect(results.prefix(2).allSatisfy { $0.isStrong })
  }

  @Test func commandsNeedMoreThanAFewLettersInsideAWord() {
    let ids = rank("rint").map(\.id)
    #expect(ids.contains(.tab(4)))
    #expect(!ids.contains(.command(.print)))
  }

  @Test func nothingMatches() {
    #expect(rank("zzzz").isEmpty)
  }

  @Test func highlightsWhatMatched() {
    let github = rank("gh").first { $0.id == .tab(1) }
    #expect(
      github?.titleRanges == [
        NSRange(location: 0, length: 1), NSRange(location: 3, length: 1),
      ])
    let pulls = rank("fiber pul").first { $0.id == .tab(7) }
    #expect(
      pulls?.titleRanges.contains(NSRange(location: 16, length: 5)) == true)
    #expect(
      pulls?.titleRanges.contains(NSRange(location: 0, length: 3)) == true)
  }

  @Test func tabsThatMatchPartlyAreSearchedForTheRest() {
    let ranked = PaletteSearch.rank(
      PaletteQuery("borrowing checker"), entries: Self.entries, now: Self.now)
    #expect(ranked.results.isEmpty)
    let references = ranked.pageText.first { $0.tabID == 5 }
    #expect(references?.required == [1])
    #expect(references?.optional == [0])
    let github = ranked.pageText.first { $0.tabID == 1 }
    #expect(github?.required == [0, 1])
  }

  @Test func shortQueriesDontSearchPageText() {
    #expect(
      PaletteSearch.rank(PaletteQuery("zq"), entries: Self.entries).pageText
        .isEmpty)
  }
}
