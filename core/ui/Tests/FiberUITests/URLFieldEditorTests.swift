import AppKit
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

  private func numbered(_ text: String) -> [String] {
    URLFieldEditor.numberedParts(in: text).map {
      (text as NSString).substring(with: $0)
    }
  }

  @Test func numberedPartsFollowTheHost() {
    let url =
      "https://stripe.com/careers/search?locations=North+America--United+States--Seattle&page=2"
    #expect(
      numbered(url) == [
        "careers", "search",
        "locations=North+America--United+States--Seattle", "page=2",
      ])
    #expect(numbered("github.com/a//b#c") == ["a", "b", "c"])
    #expect(numbered("file:///Users/a") == ["Users", "a"])
  }

  @Test func onlyNineAreNumbered() {
    #expect(numbered("x.com/1/2/3/4/5/6/7/8/9/10").last == "9")
  }

  @Test func textWithoutNumberedParts() {
    #expect(numbered("https://x.com/") == [])
    #expect(numbered("about:blank") == [])
    #expect(numbered("x.com/how to") == [])
    #expect(numbered("") == [])
  }

  @Test func optionNumberSelectsItsPartAndTheRest() throws {
    let editor = URLFieldEditor()
    editor.string = "https://x.com/search?q=cats&page=2"
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0,
        windowNumber: 0, context: nil, characters: "™",
        charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19))
    editor.keyDown(with: event)
    #expect(
      (editor.string as NSString).substring(with: editor.selectedRange())
        == "q=cats&page=2")
  }

  @Test func utf16Offsets() {
    let url = "https://例え.jp/🍣/寿司"
    #expect(tail(url, at: "寿司") == "寿司")
    #expect(tail(url, at: "🍣", offset: 1) == "🍣/寿司")
  }
}
