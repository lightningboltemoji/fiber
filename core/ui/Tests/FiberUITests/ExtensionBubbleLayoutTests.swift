import AppKit
import Testing

@testable import FiberUI

struct ExtensionBubbleLayoutTests {
  // Flipped: y grows down from the page's top.
  private let page = NSRect(x: 0, y: 0, width: 1000, height: 800)
  private let size = NSSize(width: 400, height: 500)
  private let minSize = NSSize(width: 200, height: 150)

  private func panel(beside bubble: NSRect, in bounds: NSRect? = nil)
    -> NSRect
  {
    ExtensionBubbleLayout.panelFrame(
      size: size, beside: bubble, in: bounds ?? page, gap: 8,
      minSize: minSize)
  }

  @Test func topRightHangsDownToTheLeft() {
    let bubble = NSRect(x: 940, y: 20, width: 44, height: 44)
    #expect(
      panel(beside: bubble)
        == NSRect(x: 532, y: 20, width: 400, height: 500))
  }

  @Test func bottomRightRisesToTheLeft() {
    let bubble = NSRect(x: 940, y: 736, width: 44, height: 44)
    #expect(
      panel(beside: bubble)
        == NSRect(x: 532, y: 280, width: 400, height: 500))
  }

  @Test func topLeftHangsDownToTheRight() {
    let bubble = NSRect(x: 16, y: 20, width: 44, height: 44)
    #expect(
      panel(beside: bubble)
        == NSRect(x: 68, y: 20, width: 400, height: 500))
  }

  @Test func bottomLeftRisesToTheRight() {
    let bubble = NSRect(x: 16, y: 736, width: 44, height: 44)
    #expect(
      panel(beside: bubble)
        == NSRect(x: 68, y: 280, width: 400, height: 500))
  }

  @Test func slidesToStayOnThePage() {
    // Upper half, but too low for the panel to hang all the way down.
    let bubble = NSRect(x: 940, y: 350, width: 44, height: 44)
    #expect(panel(beside: bubble).maxY == page.maxY)
    #expect(panel(beside: bubble).height == size.height)
  }

  @Test func shrinksToTheRoomBeside() {
    // Just right of the middle: 492 - 8 of room to the left.
    let bubble = NSRect(x: 492, y: 20, width: 44, height: 44)
    let frame = panel(beside: bubble)
    #expect(frame.width == 400)
    let nearer = NSRect(x: 300, y: 20, width: 44, height: 44)
    // Left of the middle, so it opens right, into 1000 - 344 - 8.
    #expect(panel(beside: nearer).minX == 352)
    let squeezed = panel(
      beside: NSRect(x: 520, y: 20, width: 44, height: 44),
      in: NSRect(x: 0, y: 0, width: 800, height: 800))
    #expect(squeezed.width == 400)
    // Right of the middle of a narrow page: 300 - 8 of room to the left.
    let narrow = panel(
      beside: NSRect(x: 300, y: 20, width: 44, height: 44),
      in: NSRect(x: 0, y: 0, width: 600, height: 800))
    #expect(narrow.width == 292)
    #expect(narrow.minX == 0)
  }

  @Test func overlapsOnlyPastItsMinimum() {
    // 150 of room to the right, under the 200 minimum: the panel keeps 200
    // and covers part of the bubble rather than leaving the page.
    let bubble = NSRect(x: 158, y: 20, width: 44, height: 44)
    let frame = panel(
      beside: bubble, in: NSRect(x: 0, y: 0, width: 360, height: 800))
    #expect(frame.width == 200)
    #expect(frame.maxX == 360)
    #expect(frame.minX < bubble.maxX)
  }

  @Test func neverLargerThanThePage() {
    let tiny = NSRect(x: 0, y: 0, width: 180, height: 120)
    let frame = panel(
      beside: NSRect(x: 130, y: 10, width: 44, height: 44), in: tiny)
    #expect(frame == tiny)
  }

  // The find bar below the toolbar, and the first two spots down the right
  // edge.
  private let findBar = NSRect(x: 664, y: 72, width: 320, height: 40)

  private func clear(_ centers: [NSPoint]) -> [NSPoint] {
    ExtensionBubbleLayout.centers(
      centers, radius: 22, clearOf: findBar, spacing: 12)
  }

  @Test func movesBelowTheFindBarAndPushesTheNextOne() {
    #expect(
      clear([NSPoint(x: 962, y: 174), NSPoint(x: 962, y: 86)])
        == [NSPoint(x: 962, y: 202), NSPoint(x: 962, y: 146)])
  }

  @Test func leavesTheRestWhereTheyAre() {
    let centers = [
      NSPoint(x: 38, y: 86), NSPoint(x: 962, y: 400),
      // Overlapping each other, as the user left them.
      NSPoint(x: 500, y: 500), NSPoint(x: 510, y: 500),
    ]
    #expect(clear(centers) == centers)
  }
}
