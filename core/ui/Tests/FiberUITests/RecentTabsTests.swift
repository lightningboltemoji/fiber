import FiberBridge
import Foundation
import Testing

@testable import FiberUI

struct RecentTabsTests {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// Tabs with IDs `ids`, each last shown or opened `minutes` before now.
  private static func tabs(_ ids: [Int], minutes: (Int) -> Double = { _ in 60 })
    -> [FiberTabState]
  {
    ids.map {
      FiberTabState(
        id: $0, title: "", url: "", favicon: nil, loading: false,
        lastActiveTime: now - minutes($0) * 60)
    }
  }

  private static func at(_ minutes: Double) -> Date {
    now + minutes * 60
  }

  @Test func listsTheActiveTabThenTheTabsLeftMostRecently() {
    let tabs = Self.tabs([1, 2, 3, 4])
    var recent = RecentTabs()
    for (minute, tabID) in [1, 3, 2, 4, 3].enumerated() {
      recent.update(tabs, activeTabID: tabID, now: Self.at(Double(minute)))
    }
    #expect(recent.ordered(tabs).map(\.tabID) == [3, 4, 2, 1])
  }

  @Test func goesByChromesTimeForTabsNotSeenActive() {
    // As after session restore: the order the tabs were last shown in.
    let tabs = Self.tabs([1, 2, 3, 4]) { [1: 30, 2: 5, 3: 120, 4: 10][$0]! }
    var recent = RecentTabs()
    recent.update(tabs, activeTabID: 3, now: Self.now)
    #expect(recent.ordered(tabs).map(\.tabID) == [3, 2, 4, 1])
  }

  @Test func aTabOpenedInTheBackgroundDoesntPassTheOneItWasOpenedFrom() {
    var recent = RecentTabs()
    recent.update(Self.tabs([1, 2]), activeTabID: 1, now: Self.now)
    // Opened from tab 1, just now.
    let tabs = Self.tabs([1, 2, 3]) { $0 == 3 ? 0 : 60 }
    recent.update(tabs, activeTabID: 2, now: Self.at(1))
    #expect(recent.ordered(tabs).map(\.tabID) == [2, 1, 3])
  }

  @Test func listsAtMostTheLimitWithTheActiveTab() {
    let tabs = Self.tabs(Array(1...40)) { Double($0) }
    var recent = RecentTabs()
    recent.update(tabs, activeTabID: 40, now: Self.now)
    let ordered = recent.ordered(tabs).map(\.tabID)
    #expect(ordered.count == RecentTabs.limit)
    #expect(ordered == [40] + Array(1..<RecentTabs.limit))
  }
}
