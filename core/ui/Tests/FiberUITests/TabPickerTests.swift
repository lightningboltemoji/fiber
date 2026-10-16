import AppKit
import FiberBridge
import Foundation
import Testing

@testable import FiberUI

@MainActor
struct TabPickerTests {
  private typealias Layout = TabPickerLayout

  private static func tabs(_ count: Int) -> [FiberTabState] {
    (1...count).map {
      FiberTabState(
        id: $0, title: "", url: "", origin: "", favicon: nil, loading: false,
        lastActiveTime: .distantPast)
    }
  }

  /// A drop at rest `depth` below the lip.
  private static func target(depth: CGFloat) -> TabPickerDropMotion.Target {
    .init(
      lipMinX: 0, lipMaxX: 400, bodyMidX: 200, bodyWidth: 300, depth: depth,
      bulgeX: 200)
  }

  @Test func countsRowsDownFromTheFirstTab() {
    #expect(Layout.row(atY: 0) == -1)
    #expect(Layout.row(atY: Layout.itemTop(0)) == 0)
    #expect(Layout.row(atY: Layout.itemTop(3) + 1) == 3)
    // The gap under a tab is still that tab's.
    #expect(Layout.row(atY: Layout.itemTop(1) - 1) == 0)
  }

  @Test func holdsItsTabsAndTheInsetBelowThem() {
    #expect(
      Layout.columnBottom(rows: 2)
        == Layout.itemTop(1) + Layout.itemHeight + Layout.inset)
    #expect(Layout.columnBottom(rows: 0) == Layout.columnBottom(rows: 1))
  }

  @Test func showsAsManyTabsAsFitDownTheWindow() {
    let model = TabPickerModel()
    model.tabs = Self.tabs(10)
    model.size = CGSize(width: 800, height: 2000)
    #expect(model.maxRows == 10)
    model.size.height = Layout.columnBottom(rows: 4) + TabPickerModel.margin
    #expect(model.maxRows == 4)
    // Always the active tab, however short the window.
    model.size.height = 20
    #expect(model.maxRows == 1)
  }

  @Test func coversATabAsTheGlassPoursOverIt() {
    let model = TabPickerModel()
    let halfLip = TabPickerModel.lipHeight / 2
    model.drop.depth = Layout.columnBottom(rows: 2) - halfLip
    #expect(model.coverage(ofRow: 1) == 1)
    #expect(model.coverage(ofRow: 2) == 0)
    model.drop.depth = Layout.itemTop(2) + Layout.itemHeight / 2 - halfLip
    #expect((0.1...0.9).contains(model.coverage(ofRow: 2)))
  }

  @Test func hangsThePreviewBesideItsTabOnlyWhereItFits() {
    let model = TabPickerModel()
    model.tabs = Self.tabs(3)
    model.activeTabID = 1
    model.highlightedTabID = 3
    model.previews = [3: NSImage(size: CGSize(width: 1, height: 1))]
    model.isExpanded = true
    model.size = CGSize(width: 1200, height: 800)
    model.columnMidX = 400
    model.drop.depth = Layout.columnBottom(rows: 3)
    let preview = model.previewRect
    let gap = TabPickerModel.previewGap
    #expect(preview?.minX == 400 + Layout.columnWidth / 2 + gap)
    #expect(preview?.minY == Layout.itemTop(2) - Layout.previewInset)
    model.isPreviewLeading = true
    #expect(model.previewRect == nil)
    model.columnMidX = 800
    #expect(model.previewRect?.maxX == 800 - Layout.columnWidth / 2 - gap)
  }

  @Test func settlesWhereItsHeaded() {
    var motion = TabPickerDropMotion(at: Self.target(depth: 0))
    motion.target = Self.target(depth: 200)
    for _ in 0..<240 {
      motion.step(1 / 120, reduceMotion: false)
    }
    #expect(motion.isSettled)
    #expect(abs(motion.drop.depth - 200) < 0.1)
    #expect(abs(motion.drop.bulge) < 0.1)
  }

  @Test func poursPastWhereItsHeadedAndSagsOnlyWithoutReduceMotion() {
    func pour(reduceMotion: Bool) -> (deepest: CGFloat, sag: CGFloat) {
      var motion = TabPickerDropMotion(at: Self.target(depth: 0))
      motion.target = Self.target(depth: 200)
      var deepest: CGFloat = 0
      var sag: CGFloat = 0
      for _ in 0..<240 {
        motion.step(1 / 120, reduceMotion: reduceMotion)
        deepest = max(deepest, motion.drop.depth)
        sag = max(sag, abs(motion.drop.bulge))
      }
      return (deepest, sag)
    }
    let lively = pour(reduceMotion: false)
    #expect(lively.deepest > 200)
    #expect(lively.sag > 1)
    let reduced = pour(reduceMotion: true)
    #expect(reduced.deepest <= 200.01)
    #expect(reduced.sag == 0)
  }

  @Test func keepsTheRimEvenAllRound() {
    let drop = TabPickerDrop(
      lipMinX: 0, lipMaxX: 400, bodyMidX: 200, bodyWidth: 300, depth: 200)
    let outer = drop.shape.path(in: .zero).boundingRect
    let inner = drop.shape.inset(by: Layout.rimWidth).path(in: .zero)
      .boundingRect
    let expected = outer.insetBy(dx: Layout.rimWidth, dy: Layout.rimWidth)
    #expect(abs(inner.minX - expected.minX) < 0.01)
    #expect(abs(inner.maxX - expected.maxX) < 0.01)
    #expect(abs(inner.maxY - expected.maxY) < 0.01)
  }

  @Test func drawsItsLipUpPastTheEdgeOnceOpen() {
    let shut = TabPickerDrop(
      lipMinX: 0, lipMaxX: 400, bodyMidX: 200, bodyWidth: 88, depth: 0)
    #expect(shut.shape.path(in: .zero).boundingRect.maxY > 0)
    #expect(shut.shape.lipMidY == 0)
    let open = TabPickerDrop(
      lipMinX: 0, lipMaxX: 400, bodyMidX: 200, bodyWidth: 300, depth: 200)
    #expect(open.shape.lipMidY + TabPickerModel.lipHeight / 2 < 0)
  }
}
