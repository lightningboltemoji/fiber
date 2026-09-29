import Foundation

/// What the user typed in the command palette, as words to match.
struct PaletteQuery: Sendable {
  struct Token: Sendable {
    let scalars: TextMatching.Scalars
    /// The last word, still being typed (no space after it yet), so it's
    /// matched as the start of a word, typos and all.
    let isOpen: Bool
    /// Written in a script without spaces between words, so it can be found
    /// inside a word of text.
    let isUnspaced: Bool
  }

  let tokens: [Token]

  init(_ text: String) {
    let words = TextMatching.words(in: text)
    let endsInWord =
      text.unicodeScalars.last.map(TextMatching.isWordScalar) ?? false
    tokens = words.enumerated().map { index, word in
      Token(
        scalars: word.scalars,
        isOpen: endsInWord && index == words.count - 1,
        isUnspaced: word.scalars.contains(where: TextMatching.isUnspaced))
    }
  }

  var isEmpty: Bool { tokens.isEmpty }

  /// Whether there's enough of it to look for in pages' text, where a letter
  /// or two starts too many words to mean anything.
  var searchesPageText: Bool {
    tokens.reduce(0) { $0 + $1.scalars.count } >= 3
  }
}

/// Text the palette matches a query against, like a tab's title or a part of
/// its URL.
struct MatchField {
  enum Target {
    case title
    case subtitle
    /// Matched, but not shown, like a command's other names.
    case hidden
  }

  let words: [TextMatching.Word]
  /// How much a match here counts, from 0 to 1.
  let weight: Double
  /// Where its ranges are, for highlighting.
  let target: Target
  /// A match on its first word counts extra: it starts the item's name (a
  /// title, a site).
  let isLeading: Bool
}

/// A tab or command, as the palette's ranking sees it.
struct MatchCandidate {
  let fields: [MatchField]

  static func tab(title: String, url: String) -> MatchCandidate {
    MatchCandidate(
      fields: [
        MatchField(
          words: TextMatching.words(in: title), weight: 1, target: .title,
          isLeading: true)
      ] + urlFields(url))
  }

  static func command(title: String, aliases: [String]) -> MatchCandidate {
    MatchCandidate(
      fields: [
        MatchField(
          words: TextMatching.words(in: title), weight: 1, target: .title,
          isLeading: true)
      ]
        + aliases.map {
          MatchField(
            words: TextMatching.words(in: $0), weight: 0.85, target: .hidden,
            isLeading: true)
        })
  }

  /// A URL as Chrome formats it for display (no https://, a Unicode host):
  /// its scheme, if shown, its host, and its path. The host's "www." and top
  /// level domain count for little, and the query and fragment for nothing.
  static func urlFields(_ url: String) -> [MatchField] {
    let text = url as NSString
    var fields: [MatchField] = []
    var hostStart = 0
    let separator = text.range(of: "://")
    if separator.location != NSNotFound {
      fields.append(
        MatchField(
          words: words(in: text, from: 0, to: separator.location), weight: 0.5,
          target: .subtitle, isLeading: false))
      hostStart = NSMaxRange(separator)
    }
    let pathSearch = NSRange(
      location: hostStart, length: text.length - hostStart)
    let slash = text.range(of: "/", options: [], range: pathSearch)
    let hostEnd = slash.location == NSNotFound ? text.length : slash.location
    var host = words(in: text, from: hostStart, to: hostEnd)
    if host.first?.scalars == Array("www".unicodeScalars) {
      host.removeFirst()
    }
    if host.count > 1, let last = host.last,
      last.scalars.allSatisfy({ $0.properties.numericType == nil })
    {
      host.removeLast()
      fields.append(
        MatchField(
          words: [last], weight: 0.3, target: .subtitle, isLeading: false))
    }
    fields.append(
      MatchField(words: host, weight: 0.9, target: .subtitle, isLeading: true))
    let rest = NSRange(location: hostEnd, length: text.length - hostEnd)
    let query = text.rangeOfCharacter(
      from: CharacterSet(charactersIn: "?#"), options: [], range: rest)
    let pathEnd = query.location == NSNotFound ? text.length : query.location
    fields.append(
      MatchField(
        words: words(in: text, from: hostEnd, to: pathEnd), weight: 0.6,
        target: .subtitle, isLeading: false))
    return fields
  }

  private static func words(in text: NSString, from start: Int, to end: Int)
    -> [TextMatching.Word]
  {
    guard end > start else {
      return []
    }
    return TextMatching.words(
      in: text.substring(with: NSRange(location: start, length: end - start))
    ).map { word in
      TextMatching.Word(
        scalars: word.scalars,
        range: NSRange(
          location: word.range.location + start, length: word.range.length),
        scalarEnds: word.scalarEnds, partStarts: word.partStarts)
    }
  }
}

/// Ranks what the command palette lists: tabs and commands whose names
/// (titles, URLs) match what's typed, and which tabs to look for it in the
/// text of. See .agents/PALETTE.md.
enum PaletteSearch {
  /// How well a word of the query matches a word of a name, from 0 to 1.
  enum Quality {
    static let exact = 1.0
    static let prefix = 0.9
    /// The start of a camel case part: "hub" in GitHub.
    static let partPrefix = 0.8
    /// Inside a word of a script without spaces.
    static let unspaced = 0.8
    /// The starts of consecutive words or parts: "nyt", "gh".
    static let initials = 0.75
    static let oneTypo = 0.65
    static let twoTypos = 0.5
    static let substring = 0.4

    /// A name matches strongly when every word of the query matches at least
    /// this well somewhere. Strong matches list first.
    static let strong = initials
    /// Commands aren't listed for anything weaker: a few letters inside a
    /// word aren't enough to mean one.
    static let command = twoTypos
  }

  enum Bonus {
    /// The first word of the query starts a title or site.
    static let leading = 0.1
    /// The query's words are in the name's order, next to each other.
    static let phrase = 0.1
    /// In order, but apart.
    static let order = 0.05
    /// Times the share of a title's words that match: "Print" is a better
    /// match for "print" than "Print CSS - MDN".
    static let coverage = 0.1
    /// Most for a tab used just now, halving every `recencyHalfLife`.
    static let recency = 0.05
    static let recencyHalfLife: TimeInterval = 6 * 3600
    /// For commands, which have no recency.
    static let command = 0.03
    /// The tab the user is on, which they rarely want to switch to.
    static let currentTab = -0.05
  }

  struct Entry {
    enum ID: Hashable {
      case tab(Int)
      case command(PaletteCommand)
    }

    let id: ID
    let candidate: MatchCandidate
    /// Nil for commands.
    let lastActive: Date?
    let isCurrent: Bool

    var isTab: Bool {
      if case .tab = id {
        return true
      }
      return false
    }
  }

  struct Result {
    let id: Entry.ID
    let isStrong: Bool
    let score: Double
    let titleRanges: [NSRange]
    let subtitleRanges: [NSRange]
  }

  /// A tab that matched some of the query's words, or none, by name: it's
  /// listed if the rest are in the text of its page.
  struct PageTextCandidate: Sendable {
    let tabID: Int
    /// The query's words that must be in one passage of the page.
    let required: [Int]
    /// Its words that matched the tab's name, which count for less there.
    let optional: [Int]
    /// How well the name matched, from 0 to 1.
    let nameScore: Double
    let titleRanges: [NSRange]
    let subtitleRanges: [NSRange]
  }

  /// Entries whose names match `query`, best first, and the tabs to look for
  /// the rest in. With an empty query, every tab: the current one, then the
  /// most recently used.
  static func rank(
    _ query: PaletteQuery, entries: [Entry], now: Date = Date()
  ) -> (results: [Result], pageText: [PageTextCandidate]) {
    guard !query.isEmpty else {
      let tabs = entries.filter(\.isTab).enumerated().sorted {
        a, b in
        if a.element.isCurrent != b.element.isCurrent {
          return a.element.isCurrent
        }
        if a.element.lastActive != b.element.lastActive {
          return (a.element.lastActive ?? .distantPast)
            > (b.element.lastActive ?? .distantPast)
        }
        return a.offset < b.offset
      }
      return (
        tabs.map {
          Result(
            id: $0.element.id, isStrong: true, score: 0, titleRanges: [],
            subtitleRanges: [])
        }, []
      )
    }
    var ranked: [(result: Result, lastActive: Date?)] = []
    var pageText: [PageTextCandidate] = []
    for entry in entries {
      let match = match(query, entry.candidate)
      if match.isComplete
        && (entry.isTab
          || match.hits.allSatisfy { $0!.quality >= Quality.command })
      {
        var score = match.score
        if entry.isTab {
          let age = max(now.timeIntervalSince(entry.lastActive ?? now), 0)
          score += Bonus.recency * pow(0.5, age / Bonus.recencyHalfLife)
          if entry.isCurrent {
            score += Bonus.currentTab
          }
        } else {
          score += Bonus.command
        }
        ranked.append(
          (
            Result(
              id: entry.id, isStrong: match.isStrong, score: score,
              titleRanges: match.titleRanges,
              subtitleRanges: match.subtitleRanges), entry.lastActive
          ))
      } else if case .tab(let tabID) = entry.id, query.searchesPageText {
        let matched = query.tokens.indices.filter { match.hits[$0] != nil }
        pageText.append(
          PageTextCandidate(
            tabID: tabID,
            required: query.tokens.indices.filter { match.hits[$0] == nil },
            optional: matched, nameScore: match.score,
            titleRanges: match.titleRanges,
            subtitleRanges: match.subtitleRanges))
      }
    }
    ranked.sort { a, b in
      if a.result.isStrong != b.result.isStrong {
        return a.result.isStrong
      }
      if a.result.score != b.result.score {
        return a.result.score > b.result.score
      }
      return (a.lastActive ?? .distantPast) > (b.lastActive ?? .distantPast)
    }
    return (ranked.map(\.result), pageText)
  }

  // MARK: Matching names

  struct Hit {
    let quality: Double
    /// `quality` times the field's weight.
    let score: Double
    let field: Int
    let firstWord: Int
    let lastWord: Int
    let ranges: [NSRange]
  }

  struct NameMatch {
    /// The best hit for each word of the query, if it has one.
    let hits: [Hit?]
    /// Whether each word of the query matches strongly somewhere, if not in
    /// its best hit.
    let strongTokens: [Bool]
    let score: Double
    let titleRanges: [NSRange]
    let subtitleRanges: [NSRange]

    var isComplete: Bool { hits.allSatisfy { $0 != nil } }
    var isStrong: Bool { strongTokens.allSatisfy { $0 } }
  }

  /// How well `candidate`'s names match `query`: each word of the query on
  /// its own, wherever it matches best, plus bonuses for how they match
  /// together.
  static func match(_ query: PaletteQuery, _ candidate: MatchCandidate)
    -> NameMatch
  {
    let fieldHits = query.tokens.map { token in
      candidate.fields.indices.compactMap {
        bestHit(token, in: candidate, field: $0)
      }
    }
    let hits = fieldHits.map { $0.max { $0.score < $1.score } }
    let found = hits.compactMap { $0 }
    var score = found.reduce(0) { $0 + $1.score } / Double(max(hits.count, 1))
    if let first = hits.first ?? nil, first.firstWord == 0,
      candidate.fields[first.field].isLeading
    {
      score += Bonus.leading
    }
    if found.count > 1, found.count == hits.count,
      found.allSatisfy({ $0.field == found[0].field })
    {
      let pairs = zip(found, found.dropFirst())
      if pairs.allSatisfy({ $1.firstWord == $0.lastWord + 1 }) {
        score += Bonus.phrase
      } else if pairs.allSatisfy({ $1.firstWord > $0.lastWord }) {
        score += Bonus.order
      }
    }
    if let title = candidate.fields.first, !title.words.isEmpty {
      let covered = Set(
        found.filter { $0.field == 0 }.flatMap { $0.firstWord...$0.lastWord })
      score +=
        Bonus.coverage * Double(covered.count) / Double(title.words.count)
    }
    func ranges(_ target: MatchField.Target) -> [NSRange] {
      found.filter { candidate.fields[$0.field].target == target }
        .flatMap(\.ranges)
    }
    return NameMatch(
      hits: hits,
      strongTokens: fieldHits.map {
        $0.contains { $0.quality >= Quality.strong }
      }, score: score, titleRanges: ranges(.title),
      subtitleRanges: ranges(.subtitle))
  }

  /// The best match for `token` in one of `candidate`'s fields, if any.
  static func bestHit(
    _ token: PaletteQuery.Token, in candidate: MatchCandidate,
    field fieldIndex: Int
  ) -> Hit? {
    let field = candidate.fields[fieldIndex]
    let query = token.scalars
    var best: Hit?
    func consider(
      _ quality: Double, _ first: Int, _ last: Int, _ ranges: [NSRange]
    ) {
      let score = quality * field.weight
      if score > best?.score ?? 0 {
        best = Hit(
          quality: quality, score: score, field: fieldIndex, firstWord: first,
          lastWord: last, ranges: ranges)
      }
    }
    for (index, word) in field.words.enumerated() {
      let scalars = word.scalars
      if scalars == query {
        consider(Quality.exact, index, index, [word.range])
        continue
      }
      if TextMatching.hasPrefix(scalars, query) {
        consider(
          Quality.prefix, index, index, [word.range(ofPrefix: query.count)])
        continue
      }
      if let part = word.partStarts.first(where: {
        TextMatching.hasPrefix(scalars, query, at: $0)
      }) {
        consider(
          Quality.partPrefix, index, index,
          [word.range(from: part, to: part + query.count)])
        continue
      }
      if token.isUnspaced || query.count >= 3,
        let start = TextMatching.firstIndex(of: query, in: scalars)
      {
        consider(
          token.isUnspaced ? Quality.unspaced : Quality.substring, index, index,
          [word.range(from: start, to: start + query.count)])
      }
      let limit = TextMatching.typoLimit(forLength: query.count)
      if limit > 0, TextMatching.couldBeTypo(query, of: scalars),
        let distance = TextMatching.editDistance(
          query, scalars, limit: limit, prefix: token.isOpen)
      {
        consider(
          distance <= 1 ? Quality.oneTypo : Quality.twoTypos, index, index,
          [word.range])
      }
    }
    if query.count >= 2, (best?.quality ?? 0) < Quality.initials,
      let initials = initialsHit(query, in: field)
    {
      consider(Quality.initials, initials.first, initials.last, initials.ranges)
    }
    return best
  }

  /// `query` split across the starts of two or more consecutive words or camel
  /// case parts: "nyt" for New York Times, "gh" for GitHub, "newyork".
  private static func initialsHit(
    _ query: TextMatching.Scalars, in field: MatchField
  ) -> (first: Int, last: Int, ranges: [NSRange])? {
    guard query.count <= 24 else {
      return nil
    }
    struct Part {
      let word: Int
      let start: Int
      let end: Int
    }
    var parts: [Part] = []
    for (index, word) in field.words.enumerated() {
      let starts = [0] + word.partStarts
      for (n, start) in starts.enumerated() {
        let end = n + 1 < starts.count ? starts[n + 1] : word.scalars.count
        parts.append(Part(word: index, start: start, end: end))
      }
    }
    var pieces: [(part: Int, length: Int)] = []
    // Longest pieces first, so "nytim" highlights all of "Tim".
    func fill(from offset: Int, part: Int) -> Bool {
      if offset == query.count {
        return pieces.count >= 2
      }
      guard part < parts.count else {
        return false
      }
      let scalars = field.words[parts[part].word].scalars
      let start = parts[part].start
      let longest = min(query.count - offset, parts[part].end - start)
      for length in stride(from: longest, through: 1, by: -1)
      where (0..<length).allSatisfy({
        scalars[start + $0] == query[offset + $0]
      }) {
        pieces.append((part, length))
        if fill(from: offset + length, part: part + 1) {
          return true
        }
        pieces.removeLast()
      }
      return false
    }
    for start in parts.indices where fill(from: 0, part: start) {
      let ranges = pieces.map { piece in
        let part = parts[piece.part]
        return field.words[part.word].range(
          from: part.start, to: part.start + piece.length)
      }
      return (
        parts[pieces.first!.part].word, parts[pieces.last!.part].word, ranges
      )
    }
    return nil
  }
}
