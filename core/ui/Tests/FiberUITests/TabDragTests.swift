import FiberBridge
import Foundation
import Testing

@testable import FiberUI

@MainActor
struct TabDragTests {
  private let rightTabID = 9

  private func tab(_ id: Int) -> FiberTabState {
    FiberTabState(
      id: id, title: "Tab \(id)", url: "example.com/\(id)",
      origin: "example.com", favicon: nil, loading: false,
      lastActiveTime: Date())
  }

  /// Three tabs in the list, and `rightTabID` in the split's spot.
  private func makeModel() -> TabOverlayModel {
    let model = TabOverlayModel()
    model.rows = [1, 2, 3].map { TabListRow(tab: tab($0)) }
    model.split = SplitPair(leftTabID: 1, rightTabID: rightTabID)
    model.splitTab = tab(rightTabID)
    model.panelFrame = CGRect(x: 0, y: 0, width: 640, height: 400)
    return model
  }

  private func spotDrag(
    toRowTop top: CGFloat = 0, target: TabDropTarget? = nil
  ) -> TabDrag {
    TabDrag(
      rowID: .tab(rightTabID), isFromSpot: true, grabOffset: 0,
      point: CGPoint(x: 320, y: top), target: target)
  }

  private func top(ofPlace place: Int) -> CGFloat {
    TabListLayout.contentInset + CGFloat(place) * TabListLayout.rowStep
  }

  @Test func theSpotsTabIsOffTheListUntilItsWithinIt() {
    let model = makeModel()
    model.tabDrag = spotDrag()
    #expect(model.draggedRow?.id == .tab(rightTabID))
    #expect(model.shownRows.map(\.id) == model.rows.map(\.id))
    #expect(model.liftedRowTop == nil)
    model.tabDrag = spotDrag(target: .split)
    #expect(model.shownRows.map(\.id) == model.rows.map(\.id))
    #expect(model.liftedRowTop == nil)
  }

  @Test func theOthersMakeRoomForTheSpotsTabWithoutItJoiningThem() {
    let model = makeModel()
    let height = model.listContentHeight
    model.tabDrag = spotDrag(toRowTop: top(ofPlace: 1), target: .list(1))
    #expect(
      model.shownRows.map(\.id) == [.tab(1), .tab(rightTabID), .tab(2), .tab(3)]
    )
    #expect(model.rows.count == 3)
    #expect(model.listContentHeight == height + TabListLayout.rowStep)
  }

  @Test func theSpotsTabCanGoAfterEveryRow() {
    let model = makeModel()
    let drag = spotDrag(toRowTop: top(ofPlace: 40))
    #expect(model.dropIndex(of: drag) == 3)
    #expect(model.liftedRowTop(of: drag) == top(ofPlace: 3))
  }

  @Test func aRowOfTheListStaysAmongItsOwnPlaces() {
    let model = makeModel()
    let drag = TabDrag(
      rowID: .tab(2), grabOffset: 0, point: CGPoint(x: 320, y: top(ofPlace: 40))
    )
    #expect(model.dropIndex(of: drag) == 2)
    #expect(model.liftedRowTop(of: drag) == top(ofPlace: 2))
  }

  @Test func theSpotsTabGoesBackIntoAnEmptyList() {
    let model = makeModel()
    model.rows = []
    model.tabDrag = spotDrag(target: .list(0))
    #expect(model.shownRows.map(\.id) == [.tab(rightTabID)])
    #expect(
      model.listContentHeight == TabListLayout.panelHeight(rows: 1))
  }

  @Test func aSpotDragIsNothingOnceItsTabLeavesTheSpot() {
    let model = makeModel()
    let height = model.listContentHeight
    model.tabDrag = spotDrag(target: .list(1))
    model.splitTab = tab(4)
    #expect(model.draggedRow == nil)
    #expect(model.shownRows.map(\.id) == model.rows.map(\.id))
    #expect(model.listContentHeight == height)
  }

  @Test func onlyAPlaceOffTheSpotChangesAnything() {
    #expect(spotDrag().staysOnSpot)
    #expect(spotDrag(target: .split).staysOnSpot)
    #expect(!spotDrag(target: .list(0)).staysOnSpot)
    #expect(!spotDrag(target: .shelf(.home)).staysOnSpot)
    let row = TabDrag(rowID: .tab(1), grabOffset: 0, point: .zero)
    #expect(!row.staysOnSpot)
  }
}
