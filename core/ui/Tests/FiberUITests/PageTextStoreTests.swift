import Foundation
import Testing

@testable import FiberUI

struct PageTextStoreTests {
  private static let rustBook = """
    References and Borrowing
    The issue with the tuple code is that we have to return the String to the calling function so we can still use it after the call.
    Instead, we can provide a reference to the String value. A reference is like a pointer in that it's an address we can follow to access the data.
    Mutable references have one big restriction: if you have a mutable reference to a value, you can have no other references to that value.
    The borrow checker rejects this code because s is still mutably borrowed when the second reference is made.
    """

  private static let recipe = """
    Weeknight shoyu ramen
    Ingredients
    Chicken stock, soy sauce, mirin, kombu, dried shiitake, fresh ramen noodles, soft-boiled eggs, scallions.
    Method
    Cook the noodles for 90 seconds, then assemble in warm bowls.
    """

  private static let news = """
    Top stories
    City council approves the new waterfront transit line
    Markets close higher as chipmakers rally on strong earnings
    """

  private func store() -> PageTextStore {
    var store = PageTextStore()
    store.setText(Self.rustBook, forTab: 1)
    store.setText(Self.recipe, forTab: 2)
    store.setText(Self.news, forTab: 3)
    return store
  }

  /// Every tab, needing all of `query`'s words.
  private func search(_ store: PageTextStore, _ query: String)
    -> [PageTextMatch]
  {
    let query = PaletteQuery(query)
    return store.search(
      query,
      in: [1, 2, 3].map {
        PaletteSearch.PageTextCandidate(
          tabID: $0, required: Array(query.tokens.indices), optional: [],
          nameScore: 0, titleRanges: [], subtitleRanges: [])
      })
  }

  private func highlighted(_ match: PageTextMatch) -> [String] {
    match.snippetRanges.map { (match.snippet as NSString).substring(with: $0) }
  }

  @Test func passagesGatherLinesAndSplitLongOnes() {
    let long = Array(repeating: "word", count: 400).joined(separator: " ")
    let passages = PageTextStore.passages(
      of: "Title\n\n  Short   line  \n•\n\(long)\nAfter")
    #expect(passages.first == "Title\nShort line")
    #expect(passages.count == 2 + 4)
    #expect(passages.last == "After")
  }

  @Test func findsWordsTogetherInAPassage() {
    let matches = search(store(), "borrow checker")
    #expect(matches.map(\.tabID) == [1])
    // Words the query's start too, as a crude stem.
    #expect(highlighted(matches[0]) == ["borrow", "checker", "borrowed"])
    #expect(matches[0].findText == "borrow checker")
  }

  @Test func forgivesTyposAndFinishesTheLastWord() {
    #expect(search(store(), "borow chekcer").map(\.tabID) == [1])
    #expect(search(store(), "ramen nood").map(\.tabID) == [2])
    #expect(highlighted(search(store(), "ramen nood")[0]).contains("noodles"))
  }

  @Test func typosAreOnlyForWordsThePagesDontHave() {
    var store = PageTextStore()
    store.setText("Lease renewal due. Rent payment sent.", forTab: 1)
    store.setText(Self.recipe, forTab: 2)
    store.setText("Print this page.", forTab: 3)
    #expect(search(store, "rmen").map(\.tabID) == [2])
    #expect(search(store, "prnt").map(\.tabID) == [3])
    #expect(search(store, "print").map(\.tabID) == [3])
  }

  @Test func snippetsMarkLineBreaks() {
    // From the start of the match's line, and on through the next ones.
    let snippet = search(store(), "stock mirin").first?.snippet ?? ""
    #expect(snippet.hasPrefix("…Chicken stock, soy sauce, mirin"))
    #expect(snippet.contains("scallions. · Method · Cook"))
  }

  @Test func wordsMustShareAPassage() {
    var store = PageTextStore()
    let filler = Array(repeating: "lorem ipsum dolor", count: 50)
      .joined(separator: " ")
    store.setText("borrow\n\(filler)\n\(filler)\nchecker", forTab: 1)
    #expect(search(store, "borrow checker").isEmpty)
  }

  @Test func findTextGrowsUntilItsUnique() {
    var store = PageTextStore()
    store.setText(
      """
      The borrow checker is strict.
      Later, the borrow checker rejects code that mutates while borrowed.
      """, forTab: 1)
    let match = search(store, "checker rejects")
    #expect(match.first?.findText == "checker rejects")
    let ambiguous = search(store, "borrow checker")
    #expect(
      ambiguous.first.map {
        [
          "The borrow checker", "the borrow checker rejects",
          "borrow checker is",
        ]
        .contains($0.findText)
      } == true)
  }

  @Test func forgetsTabsThatAreGone() {
    var store = store()
    store.keepTabs([2, 3])
    #expect(search(store, "borrow checker").isEmpty)
    #expect(search(store, "ramen").map(\.tabID) == [2])
  }

  @Test func replacingTextReplacesMatches() {
    var store = store()
    store.setText(Self.news, forTab: 1)
    #expect(search(store, "borrow").isEmpty)
    #expect(Set(search(store, "waterfront").map(\.tabID)) == [1, 3])
  }
}
