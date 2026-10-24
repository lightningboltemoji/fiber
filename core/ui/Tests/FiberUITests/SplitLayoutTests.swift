import FiberBridge
import Foundation
import Testing

@testable import FiberUI

@MainActor
struct SplitLayoutTests {
  private let bounds = CGRect(x: 0, y: 0, width: 1010, height: 600)

  @Test func sharesTheWidthAroundTheGap() {
    let (left, right) = SplitLayout.frames(in: bounds, ratio: 0.5)
    #expect(left.minX == 0)
    #expect(left.width == 500)
    #expect(right.minX == left.maxX + SplitLayout.gap)
    #expect(right.maxX == bounds.maxX)
    #expect(left.height == bounds.height && right.height == bounds.height)
  }

  @Test func keepsEachPageItsLeastWidth() {
    let (left, right) = SplitLayout.frames(in: bounds, ratio: 0.05)
    #expect(left.width == SplitLayout.minPageWidth)
    let (_, narrowRight) = SplitLayout.frames(in: bounds, ratio: 0.99)
    #expect(narrowRight.width == SplitLayout.minPageWidth)
    #expect(right.maxX == bounds.maxX)
  }

  @Test func evensOutAPageAreaTooNarrowForBoth() {
    let narrow = CGRect(x: 0, y: 0, width: 410, height: 300)
    let (left, right) = SplitLayout.frames(in: narrow, ratio: 0.9)
    #expect(left.width == 200)
    #expect(right.width == 200)
  }

  @Test func theGapsMiddleGivesTheRatioItWasLaidOutWith() {
    let (left, _) = SplitLayout.frames(in: bounds, ratio: 0.3)
    let ratio = SplitLayout.ratio(
      forGapAt: left.maxX + SplitLayout.gap / 2, in: bounds)
    #expect(abs(ratio - 0.3) < 0.002)
  }

  @Test func aGapDraggedPastAPagesLeastWidthStopsThere() {
    let room = bounds.width - SplitLayout.gap
    let most = SplitLayout.ratio(forGapAt: bounds.maxX, in: bounds)
    let least = SplitLayout.ratio(forGapAt: 0, in: bounds)
    #expect(abs(most - (room - SplitLayout.minPageWidth) / room) < 1e-9)
    #expect(abs(least - SplitLayout.minPageWidth / room) < 1e-9)
  }
}

@MainActor
struct SplitPairTests {
  private func tab(_ id: Int, lastActive: TimeInterval) -> FiberTabState {
    FiberTabState(
      id: id, title: "", url: "", origin: "", favicon: nil, loading: false,
      lastActiveTime: Date(timeIntervalSinceReferenceDate: lastActive))
  }

  private var tabs: [FiberTabState] {
    [tab(1, lastActive: 30), tab(2, lastActive: 10), tab(3, lastActive: 20)]
  }

  @Test func goesBesideTheActiveTab() {
    #expect(
      SplitPair.leftTab(beside: 2, in: nil, tabs: tabs, activeTabID: 3) == 3)
  }

  @Test func theActiveTabGoesBesideTheOneUsedLast() {
    #expect(
      SplitPair.leftTab(beside: 1, in: nil, tabs: tabs, activeTabID: 1) == 3)
  }

  @Test func besideTheOneUsedLastWhenThePinsActive() {
    #expect(
      SplitPair.leftTab(beside: 3, in: nil, tabs: tabs, activeTabID: 99) == 1)
  }

  @Test func replacesTheSplitsRightAndSwapsItsLeft() {
    let split = SplitPair(leftTabID: 1, rightTabID: 2)
    #expect(
      SplitPair.leftTab(beside: 3, in: split, tabs: tabs, activeTabID: 3) == 1)
    #expect(
      SplitPair.leftTab(beside: 1, in: split, tabs: tabs, activeTabID: 1) == 2)
  }

  @Test func needsAnotherTab() {
    #expect(
      SplitPair.leftTab(
        beside: 1, in: nil, tabs: [tab(1, lastActive: 0)], activeTabID: 1)
        == nil)
  }
}
