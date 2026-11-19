import FiberBridge
import Foundation
import QuartzCore
import Testing

@testable import FiberUI

@MainActor
struct PeekLayoutTests {
  private let bounds = CGRect(x: 0, y: 0, width: 1280, height: 820)

  @Test func insetsTheCardEvenlyAllRound() {
    for size in [
      bounds.size, CGSize(width: 480, height: 320),
      CGSize(width: 1600, height: 420),
    ] {
      let area = CGRect(origin: .zero, size: size)
      let card = PeekLayout.cardFrame(in: area)
      let inset = PeekLayout.inset(in: area)
      #expect(card == area.insetBy(dx: inset, dy: inset))
    }
  }

  @Test func narrowsTheMarginInASmallPageArea() {
    let large = CGRect(x: 0, y: 0, width: 1700, height: 1060)
    #expect(PeekLayout.inset(in: large) == PeekLayout.maxInset)
    // As narrow as a window gets.
    let narrow = CGRect(x: 0, y: 0, width: 480, height: 900)
    #expect(PeekLayout.inset(in: narrow) == PeekLayout.minInset)
    // And steadily between.
    let insets = stride(from: 480, through: 1000, by: 104).map {
      PeekLayout.inset(in: CGRect(x: 0, y: 0, width: $0, height: 1100))
    }
    #expect(insets == insets.sorted())
    #expect(Set(insets).count == insets.count)
  }

  @Test func putsTheButtonsInTheMarginBesideTheCardsTopRight() {
    for size in [bounds.size, CGSize(width: 480, height: 320)] {
      let area = CGRect(origin: .zero, size: size)
      let card = PeekLayout.cardFrame(in: area)
      let buttons = PeekLayout.buttonsFrame(beside: card, in: area)
      #expect(area.maxX - buttons.maxX >= PeekLayout.minButtonEdgeInset)
      #expect(buttons.maxY == card.maxY)
    }
    // Centered, at their largest, in a margin with room for them.
    let card = PeekLayout.cardFrame(in: bounds)
    let buttons = PeekLayout.buttonsFrame(beside: card, in: bounds)
    #expect(buttons.width == PeekLayout.maxButtonSize)
    #expect(!buttons.intersects(card))
    #expect(abs((buttons.minX - card.maxX) - (bounds.maxX - buttons.maxX)) <= 1)
  }

  @Test func shrinksTheButtonsLessThanTheMargin() {
    let narrow = CGRect(x: 0, y: 0, width: 480, height: 900)
    let card = PeekLayout.cardFrame(in: narrow)
    let buttons = PeekLayout.buttonsFrame(beside: card, in: narrow)
    #expect(buttons.width == PeekLayout.minButtonSize)
    #expect(card.maxX - buttons.minX <= 5)
    let sizes = stride(from: PeekLayout.minInset, through: 40, by: 4).map {
      PeekLayout.buttonSize(inMargin: $0)
    }
    #expect(sizes == sizes.sorted())
  }

  @Test func mapsTheLayersFrameOntoTheRect() {
    let frame = CGRect(x: 40, y: 30, width: 800, height: 600)
    let rect = CGRect(x: 300, y: 200, width: 80, height: 60)
    for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5)] {
      let transform = CATransform3DGetAffineTransform(
        PeekLayout.transform(from: frame, to: rect, anchor: anchor))
      // A layer's point, from its bounds' origin, lands at its position plus
      // the transformed offset from its anchor.
      let position = CGPoint(
        x: frame.minX + anchor.x * frame.width,
        y: frame.minY + anchor.y * frame.height)
      func place(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let offset = CGPoint(
          x: x - anchor.x * frame.width, y: y - anchor.y * frame.height
        ).applying(transform)
        return CGPoint(x: position.x + offset.x, y: position.y + offset.y)
      }
      let origin = place(0, 0)
      let corner = place(frame.width, frame.height)
      #expect(abs(origin.x - rect.minX) < 0.001)
      #expect(abs(origin.y - rect.minY) < 0.001)
      #expect(abs(corner.x - rect.maxX) < 0.001)
      #expect(abs(corner.y - rect.maxY) < 0.001)
    }
  }
}
