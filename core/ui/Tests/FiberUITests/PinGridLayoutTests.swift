import Foundation
import Testing

@testable import FiberUI

struct PinGridLayoutTests {
  /// The grid over a full-width tab overlay.
  private static let width: CGFloat = 640

  @Test func spacesCirclesEvenly() {
    let step = PinGridLayout.diameter + PinGridLayout.spacing
    #expect(
      PinGridLayout.origin(of: 1, width: Self.width)
        == CGPoint(x: step, y: -PinGridLayout.diameter))
    // As many as fit in the panel's width, then the next row up.
    let columns = PinGridLayout.columns(width: Self.width)
    let last = PinGridLayout.origin(of: columns - 1, width: Self.width)
    #expect(last.x + PinGridLayout.diameter <= Self.width)
    #expect(last.x + step + PinGridLayout.diameter > Self.width)
    #expect(
      PinGridLayout.origin(of: columns, width: Self.width)
        == CGPoint(x: 0, y: -step - PinGridLayout.diameter))
  }

  @Test func growsARowAtATime() {
    let columns = PinGridLayout.columns(width: Self.width)
    let row = PinGridLayout.diameter
    #expect(PinGridLayout.height(count: 0, width: Self.width) == 0)
    #expect(PinGridLayout.height(count: columns, width: Self.width) == row)
    #expect(
      PinGridLayout.height(count: columns + 1, width: Self.width)
        == 2 * row + PinGridLayout.spacing)
  }

  @Test func hitsCirclesNotTheGapsOrCorners() {
    let center = PinGridLayout.diameter / 2
    let second = PinGridLayout.origin(of: 1, width: Self.width)
    #expect(
      PinGridLayout.hit(
        at: CGPoint(x: second.x + center, y: second.y + center), count: 3,
        open: nil, width: Self.width)?.index == 1)
    #expect(
      PinGridLayout.hit(
        at: CGPoint(x: second.x - 2, y: second.y + center), count: 3,
        open: nil, width: Self.width) == nil)
    #expect(
      PinGridLayout.hit(
        at: CGPoint(x: 1, y: second.y + 1), count: 3, open: nil,
        width: Self.width) == nil)
  }

  @Test func opensAPinAroundItsIconAndPartsItsRow() {
    let columns = PinGridLayout.columns(width: Self.width)
    let button = PinGridLayout.buttonWidth
    let open = OpenPin(index: 1, hasBack: true)
    func frame(_ index: Int, _ open: OpenPin?) -> CGRect {
      PinGridLayout.frame(of: index, open: open, width: Self.width)
    }
    // The icon stays put, with a button either side.
    #expect(frame(1, open).minX == frame(1, nil).minX - button)
    #expect(frame(1, open).width == PinGridLayout.diameter + 2 * button)
    #expect(frame(0, open).minX == frame(0, nil).minX - button)
    #expect(frame(2, open).minX == frame(2, nil).minX + button)
    // Other rows stay.
    #expect(frame(columns + 1, open) == frame(columns + 1, nil))
    // At its pinned page, it has only Close, and grows only right.
    let home = OpenPin(index: 1, hasBack: false)
    #expect(frame(1, home).minX == frame(1, nil).minX)
    #expect(frame(0, home) == frame(0, nil))
  }

  @Test func hitsAnOpenPinsButtons() {
    let open = OpenPin(index: 0, hasBack: true)
    let capsule = PinGridLayout.frame(of: 0, open: open, width: Self.width)
    func part(atX x: CGFloat) -> PinPart? {
      PinGridLayout.hit(
        at: CGPoint(x: x, y: capsule.midY), count: 3, open: open,
        width: Self.width)?.part
    }
    // Back reaches past the grid's left edge.
    #expect(capsule.minX < 0)
    #expect(part(atX: capsule.minX + 10) == .back)
    #expect(part(atX: capsule.midX) == .icon)
    #expect(part(atX: capsule.maxX - 10) == .close)
    let next = PinGridLayout.frame(of: 1, open: open, width: Self.width)
    #expect(
      PinGridLayout.hit(
        at: CGPoint(x: next.midX, y: next.midY), count: 3, open: open,
        width: Self.width)?.index == 1)
  }

  @Test func coversTheGapsButNotPastTheLastCircle() {
    let step = PinGridLayout.diameter + PinGridLayout.spacing
    let middle = -PinGridLayout.diameter / 2
    #expect(
      PinGridLayout.covers(
        CGPoint(x: PinGridLayout.diameter + 2, y: middle), count: 3,
        width: Self.width))
    #expect(
      !PinGridLayout.covers(
        CGPoint(x: 3 * step + 10, y: middle), count: 3, width: Self.width))
    // Above the only row, and on the panel below it.
    #expect(
      !PinGridLayout.covers(
        CGPoint(x: 10, y: -step - 10), count: 3, width: Self.width))
    #expect(
      !PinGridLayout.covers(CGPoint(x: 10, y: 10), count: 3, width: Self.width))
  }

  @Test func dropsADraggedPinInTheNearestPlace() {
    let third = PinGridLayout.origin(of: 2, width: Self.width)
    let nearThird = CGPoint(
      x: third.x + PinGridLayout.diameter / 2 + 10,
      y: third.y + PinGridLayout.diameter / 2 + 10)
    #expect(
      PinGridLayout.nearestIndex(to: nearThird, count: 4, width: Self.width)
        == 2)
    // Past the last pin, or off the grid, it goes to the nearest end.
    #expect(
      PinGridLayout.nearestIndex(
        to: CGPoint(x: Self.width, y: -500), count: 4, width: Self.width) == 3)
    #expect(
      PinGridLayout.nearestIndex(
        to: CGPoint(x: -100, y: 100), count: 4, width: Self.width) == 0)
    // Above the first row, into the next.
    let columns = PinGridLayout.columns(width: Self.width)
    let first = PinGridLayout.origin(of: 0, width: Self.width)
    #expect(
      PinGridLayout.nearestIndex(
        to: CGPoint(x: first.x + 10, y: first.y - 30), count: columns + 2,
        width: Self.width) == columns)
  }
}
