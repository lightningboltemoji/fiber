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
      PinGridLayout.index(
        at: CGPoint(x: second.x + center, y: second.y + center), count: 3,
        width: Self.width) == 1)
    #expect(
      PinGridLayout.index(
        at: CGPoint(x: second.x - 2, y: second.y + center), count: 3,
        width: Self.width) == nil)
    #expect(
      PinGridLayout.index(
        at: CGPoint(x: 1, y: second.y + 1), count: 3, width: Self.width)
        == nil)
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
