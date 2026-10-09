import Testing

@testable import FiberUI

@MainActor
struct TabNumberTests {
  /// What typing `digits` in turn makes, of `count` tabs: each number, and
  /// whether it's complete, until one has no tab.
  private func typing(_ digits: [Int], count: Int) -> [String] {
    var typed: Int?
    var made: [String] = []
    for digit in digits {
      guard
        let (number, isComplete) = TabOverlay.tabNumber(
          typing: digit, after: typed, count: count)
      else {
        made.append("none")
        break
      }
      made.append(isComplete ? "\(number)" : "\(number)…")
      typed = number
    }
    return made
  }

  @Test func fewerThanTenAreCompleteAtOnce() {
    #expect(typing([3], count: 9) == ["3"])
    #expect(typing([1], count: 9) == ["1"])
  }

  @Test func waitsWhileALongerNumberCouldFollow() {
    #expect(typing([1, 2], count: 15) == ["1…", "12"])
    #expect(typing([1, 0], count: 15) == ["1…", "10"])
    #expect(typing([2], count: 15) == ["2"])
    #expect(typing([1, 2, 3], count: 150) == ["1…", "12…", "123"])
    #expect(typing([1, 5], count: 150) == ["1…", "15…"])
    #expect(typing([1, 5], count: 149) == ["1…", "15"])
  }

  @Test func numbersWithoutATab() {
    #expect(typing([0], count: 15) == ["none"])
    #expect(typing([1, 7], count: 15) == ["1…", "none"])
    #expect(typing([1], count: 0) == ["none"])
  }
}
