import Foundation
import Testing

@testable import FiberUI

struct PinGridLayoutTests {
  private static let width = TabListLayout.panelWidth

  @Test func spacesCirclesLikeTheToolbarsCapsules() {
    let step = PinGridLayout.diameter + Toolbar.spacing
    #expect(PinGridLayout.origin(of: 1, width: Self.width).x == step)
    // As many as fit in the sidebar's width, then the next row.
    let columns = PinGridLayout.columns(width: Self.width)
    let last = PinGridLayout.origin(of: columns - 1, width: Self.width)
    #expect(last.x + PinGridLayout.diameter <= Self.width)
    #expect(last.x + step + PinGridLayout.diameter > Self.width)
    #expect(
      PinGridLayout.origin(of: columns, width: Self.width)
        == CGPoint(x: 0, y: step))
  }

  @Test func growsARowAtATime() {
    let columns = PinGridLayout.columns(width: Self.width)
    let row = PinGridLayout.diameter
    #expect(PinGridLayout.height(count: 0, width: Self.width) == 0)
    #expect(PinGridLayout.height(count: columns, width: Self.width) == row)
    #expect(
      PinGridLayout.height(count: columns + 1, width: Self.width)
        == 2 * row + Toolbar.spacing)
  }

  @Test func hitsCirclesNotTheGapsOrCorners() {
    let center = PinGridLayout.diameter / 2
    let second = PinGridLayout.origin(of: 1, width: Self.width)
    #expect(
      PinGridLayout.index(
        at: CGPoint(x: second.x + center, y: center), count: 3,
        width: Self.width) == 1)
    #expect(
      PinGridLayout.index(
        at: CGPoint(x: second.x - 2, y: center), count: 3, width: Self.width)
        == nil)
    #expect(
      PinGridLayout.index(at: CGPoint(x: 1, y: 1), count: 3, width: Self.width)
        == nil)
  }

  @Test func dropsADraggedPinInTheNearestPlace() {
    let third = PinGridLayout.origin(of: 2, width: Self.width)
    let nearThird = CGPoint(
      x: third.x + PinGridLayout.diameter / 2 + 10,
      y: PinGridLayout.diameter / 2 + 10)
    #expect(
      PinGridLayout.nearestIndex(to: nearThird, count: 4, width: Self.width)
        == 2)
    // Past the last pin, or off the grid, it goes to the nearest end.
    #expect(
      PinGridLayout.nearestIndex(
        to: CGPoint(x: Self.width, y: 500), count: 4, width: Self.width) == 3)
    #expect(
      PinGridLayout.nearestIndex(
        to: CGPoint(x: -100, y: -100), count: 4, width: Self.width) == 0)
  }
}
