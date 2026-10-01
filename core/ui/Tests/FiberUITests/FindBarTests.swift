import Testing

@testable import FiberUI

@MainActor
struct FindBarTests {
  @Test func countText() {
    #expect(FindBar.countText(-1, activeMatch: 0) == "")
    #expect(FindBar.countText(0, activeMatch: 0) == "No matches")
    #expect(FindBar.countText(1, activeMatch: 0) == "1 match")
    #expect(FindBar.countText(12, activeMatch: 0) == "12 matches")
    #expect(FindBar.countText(12, activeMatch: 3) == "3 of 12")
  }
}
