import FiberBridge
import Foundation
import QuartzCore
import Testing

@testable import FiberUI

@MainActor
struct PeekLayoutTests {
  private let bounds = CGRect(x: 0, y: 0, width: 1280, height: 820)

  @Test func insetsTheCardEvenlyWithinThePageArea() {
    let card = PeekLayout.cardFrame(in: bounds)
    #expect(bounds.contains(card))
    #expect(card.minX - bounds.minX == bounds.maxX - card.maxX)
    #expect(card.minY - bounds.minY == bounds.maxY - card.maxY)
  }

  @Test func putsTheButtonsInTheMarginBesideTheCardsTopRight() {
    for size in [bounds.size, CGSize(width: 480, height: 320)] {
      let area = CGRect(origin: .zero, size: size)
      let card = PeekLayout.cardFrame(in: area)
      let buttons = PeekLayout.buttonsFrame(beside: card)
      #expect(area.contains(buttons))
      #expect(!buttons.intersects(card))
      #expect(buttons.maxY == card.maxY)
      #expect(buttons.minX - card.maxX == PeekLayout.buttonSpacing)
    }
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
