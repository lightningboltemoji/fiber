import Foundation
import Testing

@testable import FiberUI

@MainActor
struct ShelfBarLayoutTests {
  @Test func overlapsSegmentsInsideTheRim() {
    let widths: [CGFloat] = [40, 60, 80]
    let overlap = ShelfBarLayout.segmentOverlap
    let rim = ShelfBarLayout.rimWidth
    let frames = ShelfBarLayout.segmentFrames(widths: widths)
    #expect(frames[0].minX == rim)
    #expect(frames[1].minX == frames[0].maxX - overlap)
    #expect(frames[2].maxX == rim + 180 - 2 * overlap)
    #expect(frames.allSatisfy { $0.height == ShelfBarLayout.segmentHeight })
    #expect(
      ShelfBarLayout.contentWidth(segmentWidths: widths)
        == frames[2].maxX + rim)
  }

  @Test func measuresTheRimAloneWithNoSegments() {
    #expect(
      ShelfBarLayout.contentWidth(segmentWidths: [])
        == 2 * ShelfBarLayout.rimWidth)
  }

  @Test func homeComesFirstAndNamesWiden() {
    let widths = ShelfBarLayout.segmentWidths(names: ["Later", "Trip to Lisbon"])
    #expect(widths.count == 3)
    #expect(widths[0] == ShelfBarLayout.homeWidth)
    #expect(widths[2] > widths[1])
  }

  @Test func hitsTheSegmentUnderAScrolledPoint() {
    let widths: [CGFloat] = [40, 60, 80]
    let rim = ShelfBarLayout.rimWidth
    #expect(ShelfBarLayout.segment(at: rim + 10, scroll: 0, widths: widths) == 0)
    #expect(ShelfBarLayout.segment(at: rim + 50, scroll: 0, widths: widths) == 1)
    // Scrolled 60 along, the same point is 60 further into the segments.
    #expect(
      ShelfBarLayout.segment(at: rim + 50, scroll: 60, widths: widths) == 2)
    #expect(
      ShelfBarLayout.segment(at: rim + 500, scroll: 0, widths: widths) == nil)
  }

  @Test func dividesAnOverlapHalfwayBetweenTitles() {
    let widths: [CGFloat] = [40, 60, 80]
    let frames = ShelfBarLayout.segmentFrames(widths: widths)
    let segment = { ShelfBarLayout.segment(at: $0, scroll: 0, widths: widths) }
    let divide = frames[0].maxX - ShelfBarLayout.segmentOverlap / 2
    #expect(segment(divide - 1) == 0)
    #expect(segment(divide + 1) == 1)
    // The last has no neighbor to divide with, so it keeps its whole end.
    #expect(segment(frames[2].maxX) == 2)
    #expect(segment(frames[0].minX - 1) == nil)
  }

  @Test func glowsOnlyOnASegmentTheCapsuleIsNotOn() {
    let model = ShelfBarModel()
    #expect(!model.isGlowing)
    model.hoveredPart = .button
    #expect(!model.isGlowing)
    model.hoveredPart = .segment(model.segment)
    #expect(!model.isGlowing)
    model.hoveredPart = .segment(.shelf("later"))
    #expect(model.isGlowing)
    model.dropTarget = .shelf("later")
    #expect(!model.isGlowing)
  }

  @Test func widensTheButtonToUndo() {
    #expect(ShelfBarLayout.buttonWidth(isUndo: false) == ShelfBarLayout.height)
    #expect(
      ShelfBarLayout.buttonWidth(isUndo: true) > ShelfBarLayout.height)
  }
}
