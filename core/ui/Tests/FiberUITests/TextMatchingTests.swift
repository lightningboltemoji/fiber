import Foundation
import Testing

@testable import FiberUI

struct TextMatchingTests {
  private func scalars(_ text: String) -> TextMatching.Scalars {
    Array(text.unicodeScalars)
  }

  @Test func editDistance() {
    #expect(
      TextMatching.editDistance(scalars("github"), scalars("github"), limit: 2)
        == 0)
    // A swap of neighbors is one edit.
    #expect(
      TextMatching.editDistance(scalars("githbu"), scalars("github"), limit: 1)
        == 1)
    #expect(
      TextMatching.editDistance(scalars("gthb"), scalars("github"), limit: 1)
        == nil)
    #expect(
      TextMatching.editDistance(scalars("gthb"), scalars("github"), limit: 2)
        == 2)
  }

  @Test func prefixEditDistance() {
    // Against the start of the word: the rest is still to be typed.
    #expect(
      TextMatching.editDistance(
        scalars("githb"), scalars("github"), limit: 1, prefix: true) == 1)
    #expect(
      TextMatching.editDistance(
        scalars("borow"), scalars("borrowing"), limit: 1, prefix: true) == 1)
    #expect(
      TextMatching.editDistance(
        scalars("brrwing"), scalars("borrowing"), limit: 1, prefix: true)
        == nil)
    // Not by dropping letters of a short word: "ren" starts too much.
    #expect(
      TextMatching.editDistance(
        scalars("rmen"), scalars("renewal"), limit: 1, prefix: true) == nil)
    #expect(
      TextMatching.editDistance(
        scalars("gitthub"), scalars("github"), limit: 2, prefix: true) == 1)
  }

  @Test func wordsAreFoldedWithTheirRanges() {
    let words = TextMatching.words(in: "Café Déjà-Vu, 2026")
    #expect(
      words.map { String(String.UnicodeScalarView($0.scalars)) } == [
        "cafe", "deja", "vu", "2026",
      ])
    #expect(
      words.map(\.range) == [
        NSRange(location: 0, length: 4), NSRange(location: 5, length: 4),
        NSRange(location: 10, length: 2), NSRange(location: 14, length: 4),
      ])
  }

  @Test func partsOfCamelCaseAndDigits() {
    let words = TextMatching.words(in: "GitHub HTML5Parser iPhone")
    #expect(words.map(\.partStarts) == [[3], [4, 5], [1]])
    #expect(
      words[0].range(from: 3, to: 6) == NSRange(location: 3, length: 3))
  }

  @Test func terms() {
    #expect(
      TextMatching.terms(in: "The Borrow-Checker's rules\nSÜSS")
        == ["the", "borrow", "checker", "s", "rules", "suss"])
  }
}
