import AppKit
import FiberBridge
import Testing

@testable import FiberUI

struct TabListRowTests {
  private static func page(tabID: Int) -> FiberPinState {
    FiberPinState(
      id: "page", title: "The Quiet Web", url: "longreads.example/quiet-web",
      favicon: nil, tabID: tabID, loading: false, atPinnedURL: true)
  }

  @Test func showsAClosedPageAsItWasSaved() {
    let row = TabListRow(page: Self.page(tabID: 0), tab: nil)
    #expect(row.id == .page("page"))
    #expect(row.isClosed)
    #expect(row.title == "The Quiet Web")
    #expect(row.origin == "longreads.example")
  }

  @Test func showsAnOpenPageAsItsTabIs() {
    let tab = FiberTabState(
      id: 7, title: "Elsewhere", url: "other.example/page",
      origin: "other.example", favicon: nil, loading: true,
      lastActiveTime: Date())
    let row = TabListRow(page: Self.page(tabID: 7), tab: tab)
    // The row stays the page's as its tab comes and goes.
    #expect(row.id == .page("page"))
    #expect(!row.isClosed)
    #expect(row.tabID == 7)
    #expect(row.title == "Elsewhere")
    #expect(row.isLoading)
  }

  @Test func keepsASchemesOriginWhole() {
    let page = FiberPinState(
      id: "settings", title: "Settings", url: "fiber://settings/appearance",
      favicon: nil, tabID: 0, loading: false, atPinnedURL: false)
    #expect(TabListRow(page: page, tab: nil).origin == "fiber://settings")
  }
}
