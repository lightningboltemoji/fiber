import Foundation

/// How the command palette compares text: case, accents and width folded
/// away, and split into words at anything that isn't a letter, digit or mark.
enum TextMatching {
  typealias Scalars = [Unicode.Scalar]

  /// A word of some text: folded for matching, and where it is in the text.
  struct Word {
    let scalars: Scalars
    /// In UTF-16 code units, like NSString.
    let range: NSRange
    /// Where each folded scalar ends in the text, from the word's start (in
    /// UTF-16 code units). Nil when folding changed the number of scalars, so
    /// only whole-word ranges are known.
    let scalarEnds: [Int]?
    /// Where camel case starts a new part ("GitHub": Hub), or digits start or
    /// end ("HTML5"), as offsets into `scalars`.
    let partStarts: [Int]

    /// The range of its first `count` scalars in the text.
    func range(ofPrefix count: Int) -> NSRange {
      range(from: 0, to: count)
    }

    /// The range of its scalars `start..<end` in the text.
    func range(from start: Int, to end: Int) -> NSRange {
      guard let scalarEnds, end <= scalarEnds.count, start < end else {
        return range
      }
      let lower = start == 0 ? 0 : scalarEnds[start - 1]
      return NSRange(
        location: range.location + lower, length: scalarEnds[end - 1] - lower)
    }
  }

  static func fold(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: nil)
  }

  static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.isASCII {
      let value = scalar.value
      return (0x30...0x39).contains(value) || (0x41...0x5A).contains(value)
        || (0x61...0x7A).contains(value)
    }
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
      .otherLetter, .decimalNumber, .letterNumber, .otherNumber,
      .nonspacingMark, .spacingMark, .enclosingMark:
      return true
    default:
      return false
    }
  }

  /// Scripts written without spaces between words, where a word of text can
  /// hold many words of the query.
  static func isUnspaced(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF,
      0xF900...0xFAFF, 0x20000...0x2FA1F:
      return true
    default:
      return false
    }
  }

  /// The words of `text`, each folded.
  static func words(in text: String) -> [Word] {
    var words: [Word] = []
    var start: Int?
    var scalars = String.UnicodeScalarView()
    var offset = 0
    func finish() {
      guard let wordStart = start else {
        return
      }
      let folded = Array(fold(String(scalars)).unicodeScalars)
      var ends: [Int]?
      var partStarts: [Int] = []
      if folded.count == scalars.count {
        var end = 0
        ends = scalars.map {
          end += $0.utf16.count
          return end
        }
        partStarts = Self.partStarts(in: Array(scalars))
      }
      words.append(
        Word(
          scalars: folded,
          range: NSRange(location: wordStart, length: offset - wordStart),
          scalarEnds: ends, partStarts: partStarts))
      start = nil
      scalars.removeAll(keepingCapacity: true)
    }
    for scalar in text.unicodeScalars {
      if isWordScalar(scalar) {
        if start == nil {
          start = offset
        }
        scalars.append(scalar)
      } else {
        finish()
      }
      offset += scalar.utf16.count
    }
    finish()
    return words
  }

  /// The folded words of `text`, without where they are: for indexing lots of
  /// text.
  static func terms(in text: String) -> [String] {
    var terms: [String] = []
    var current = String.UnicodeScalarView()
    for scalar in fold(text).unicodeScalars {
      if isWordScalar(scalar) {
        current.append(scalar)
      } else if !current.isEmpty {
        terms.append(String(current))
        current.removeAll(keepingCapacity: true)
      }
    }
    if !current.isEmpty {
      terms.append(String(current))
    }
    return terms
  }

  /// Offsets into `original` (a word before folding, which loses case) where
  /// camel case or digits start a new part.
  private static func partStarts(in original: Scalars) -> [Int] {
    var starts: [Int] = []
    for index in original.indices.dropFirst() {
      let scalar = original[index].properties
      let previous = original[index - 1].properties
      let isDigit = scalar.numericType != nil
      let wasDigit = previous.numericType != nil
      if (scalar.isUppercase && !previous.isUppercase && !wasDigit)
        || isDigit != wasDigit
      {
        starts.append(index)
      }
    }
    return starts
  }

  /// How many typos a word of `length` scalars may have and still match.
  static func typoLimit(forLength length: Int) -> Int {
    switch length {
    case ..<4: 0
    case 4...6: 1
    default: 2
    }
  }

  /// Whether `word` could be a typo of `query` at all: typos rarely hit the
  /// first letter, so it has to match, unless the first two are swapped.
  static func couldBeTypo(_ query: Scalars, of word: Scalars) -> Bool {
    guard let first = query.first, let wordFirst = word.first else {
      return false
    }
    return first == wordFirst
      || (query.count > 1 && word.count > 1 && query[0] == word[1]
        && query[1] == word[0])
  }

  /// The optimal string alignment distance between `a` and `b` (edits,
  /// counting a swap of neighbors as one), or nil if it's over `limit`. With
  /// `prefix`, the least distance between `a` and a prefix of `b`: one as
  /// long as `a`, or nearly, since dropping letters of a short word leaves a
  /// start too many words share ("rmen" isn't "ren…").
  static func editDistance(
    _ a: Scalars, _ b: Scalars, limit: Int, prefix: Bool = false
  ) -> Int? {
    let bLength = prefix ? min(b.count, a.count + limit) : b.count
    if !prefix, abs(a.count - bLength) > limit {
      return nil
    }
    if a.isEmpty {
      return prefix ? 0 : (bLength <= limit ? bLength : nil)
    }
    // Rows of the table for a[..<i-2], a[..<i-1] and a[..<i], against b[..<j].
    var older = [Int](repeating: 0, count: bLength + 1)
    var previous = Array(0...bLength)
    var current = [Int](repeating: 0, count: bLength + 1)
    for i in 1...a.count {
      current[0] = i
      var rowMin = i
      if bLength > 0 {
        for j in 1...bLength {
          let cost = a[i - 1] == b[j - 1] ? 0 : 1
          var value = min(
            previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
          if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
            value = min(value, older[j - 2] + 1)
          }
          current[j] = value
          rowMin = min(rowMin, value)
        }
      }
      if rowMin > limit {
        return nil
      }
      (older, previous, current) = (previous, current, older)
    }
    let shortest = max(a.count - limit, min(a.count, minimumPrefix))
    let distance =
      prefix
      ? previous[min(shortest, bLength)...bLength].min()!
      : previous[bLength]
    return distance <= limit ? distance : nil
  }

  /// The fewest letters of a word a prefix match may drop the query to.
  private static let minimumPrefix = 5

  static func hasPrefix(
    _ scalars: Scalars, _ prefix: Scalars, at start: Int = 0
  )
    -> Bool
  {
    guard scalars.count - start >= prefix.count else {
      return false
    }
    for index in prefix.indices where scalars[start + index] != prefix[index] {
      return false
    }
    return true
  }

  /// Where `needle` first occurs in `scalars`, if it does.
  static func firstIndex(of needle: Scalars, in scalars: Scalars) -> Int? {
    guard !needle.isEmpty, scalars.count >= needle.count else {
      return nil
    }
    for start in 0...(scalars.count - needle.count)
    where hasPrefix(scalars, needle, at: start) {
      return start
    }
    return nil
  }
}
