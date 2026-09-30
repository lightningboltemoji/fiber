import Foundation
import Testing

@testable import FiberUI

@MainActor
struct URLFieldEditorTests {
  /// The tail selected by a click on the first `part` in `text`, or on
  /// `offset` characters into it.
  private func tail(_ text: String, at part: String, offset: Int = 0)
    -> String?
  {
    let location = (text as NSString).range(of: part).location + offset
    return URLFieldEditor.tailRange(in: text, at: location).map {
      (text as NSString).substring(with: $0)
    }
  }

  @Test func path() {
    let url = "https://reddit.com/r/abc/some/thread"
    #expect(tail(url, at: "abc") == "abc/some/thread")
    #expect(tail(url, at: "abc", offset: 2) == "abc/some/thread")
    #expect(tail(url, at: "thread") == "thread")
    #expect(tail(url, at: "reddit") == "reddit.com/r/abc/some/thread")
    #expect(tail(url, at: "https") == url)
  }

  @Test func separatorsBelongToThePartAfter() {
    let url = "https://reddit.com/r/abc"
    #expect(tail(url, at: "/abc") == "abc")
    #expect(tail(url, at: "://", offset: 1) == "reddit.com/r/abc")
    #expect(tail("file:///Users/a", at: "///") == "Users/a")
    #expect(tail("https://x.com/a/", at: "a/", offset: 1) == nil)
  }

  @Test func queryAndFragment() {
    let url = "https://x.com/search?q=cats&page=2#results"
    #expect(tail(url, at: "search") == "search?q=cats&page=2#results")
    #expect(tail(url, at: "page") == "page=2#results")
    #expect(tail(url, at: "?") == "q=cats&page=2#results")
    #expect(tail(url, at: "results") == "results")
  }

  @Test func searchesHaveNoParts() {
    #expect(tail("how to cook rice", at: "cook") == nil)
    #expect(URLFieldEditor.tailRange(in: "", at: 0) == nil)
    #expect(URLFieldEditor.tailRange(in: "x.com", at: 5) == nil)
  }

  @Test func utf16Offsets() {
    let url = "https://例え.jp/🍣/寿司"
    #expect(tail(url, at: "寿司") == "寿司")
    #expect(tail(url, at: "🍣", offset: 1) == "🍣/寿司")
  }
}
