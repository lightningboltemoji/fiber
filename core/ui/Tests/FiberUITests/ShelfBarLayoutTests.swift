import Foundation
import Testing

@testable import FiberUI

@MainActor
struct ShelfBarLayoutTests {
  @Test func putsSegmentsSideBySideInsideTheRim() {
    let widths: [CGFloat] = [40, 60, 80]
    let frames = ShelfBarLayout.segmentFrames(widths: widths)
    #expect(frames[0].minX == ShelfBarLayout.rimWidth)
    #expect(frames[1].minX == frames[0].maxX)
    #expect(frames[2].maxX == ShelfBarLayout.rimWidth + 180)
    #expect(frames.allSatisfy { $0.height == ShelfBarLayout.segmentHeight })
    #expect(
      ShelfBarLayout.contentWidth(segmentWidths: widths)
        == 180 + 2 * ShelfBarLayout.rimWidth)
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

  @Test func widensTheButtonToUndo() {
    #expect(ShelfBarLayout.buttonWidth(isUndo: false) == ShelfBarLayout.height)
    #expect(
      ShelfBarLayout.buttonWidth(isUndo: true) > ShelfBarLayout.height)
  }
}
