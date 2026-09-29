import Foundation

/// A tab whose page has the query's words, in one passage.
struct PageTextMatch: Sendable {
  let tabID: Int
  let score: Double
  /// The words around the match, on one line.
  let snippet: String
  let snippetRanges: [NSRange]
  /// Text from the passage that finds the match in the page, and likely only
  /// it.
  let findText: String
}

/// The text of the pages in a profile's tabs, for the command palette to
/// search. Its work happens on a queue of its own, in the order it's asked.
final class PageTextIndex: @unchecked Sendable {
  private let queue = DispatchQueue(
    label: "Fiber.PageTextIndex", qos: .userInitiated)
  /// Only touched on `queue`.
  private var store = PageTextStore()

  func setText(_ text: String, forTab tabID: Int) {
    queue.async { self.store.setText(text, forTab: tabID) }
  }

  /// Forgets the text of tabs that are gone.
  func keepTabs(_ tabIDs: Set<Int>) {
    queue.async { self.store.keepTabs(tabIDs) }
  }

  func search(
    _ query: PaletteQuery, in candidates: [PaletteSearch.PageTextCandidate],
    completion: @escaping @Sendable @MainActor ([PageTextMatch]) -> Void
  ) {
    queue.async {
      let matches = self.store.search(query, in: candidates)
      DispatchQueue.main.async {
        MainActor.assumeIsolated { completion(matches) }
      }
    }
  }
}

/// Pages' text split into passages of about a paragraph, indexed by word.
/// Search scores passages with BM25, expanding each word of the query to the
/// indexed words it's a prefix or likely typo of. See .agents/PALETTE.md.
struct PageTextStore {
  /// Lines (the page's blocks) are gathered into passages of about this many
  /// words; longer lines are split.
  static let wordsPerPassage = 100
  static let resultLimit = 20

  private enum BM25 {
    static let k1 = 1.2
    static let b = 0.75
  }

  /// How much a word of the query counts when it matched an indexed word by
  /// its start (while being typed, or as a crude stem), or with typos.
  private enum Weight {
    static let exact = 1.0
    static let openPrefix = 0.9
    static let prefix = 0.7
    static let unspaced = 0.8
    static let oneTypo = 0.65
    static let twoTypos = 0.5
    /// A word of the query that also matched the tab's name.
    static let optional = 0.5
    /// Times the share of the query's word pairs that are side by side in
    /// the passage.
    static let phrase = 0.3
    /// Times how well the tab's name matched.
    static let name = 0.5
  }

  private enum Expansion {
    static let prefixes = 32
    static let typos = 16
    static let unspaced = 32
    /// A word of the query is only taken for a typo if the pages have it, or
    /// words it starts, in fewer passages than this: most words that look
    /// like typos of others aren't.
    static let typoGate = 3
  }

  private struct Posting {
    let passage: Int32
    let count: Int32
  }

  private struct Page {
    /// Lines separated by "\n", other whitespace collapsed to one space.
    var passages: [String] = []
    /// In words.
    var lengths: [Int32] = []
    var postings: [Int32: [Posting]] = [:]
    var totalLength = 0
  }

  private var pages: [Int: Page] = [:]
  private var terms: [TextMatching.Scalars] = []
  private var termIDs: [String: Int32] = [:]
  /// For each term, how many passages have it. Zero for terms that are gone.
  private var passageFrequency: [Int32] = []
  private var termsByFirstScalar: [Unicode.Scalar: [Int32]] = [:]
  private var unspacedTerms: [Int32] = []
  private var liveTermCount = 0
  private var passageCount = 0
  private var totalLength = 0

  mutating func setText(_ text: String, forTab tabID: Int) {
    removePage(tabID)
    var page = Page()
    for passage in Self.passages(of: text) {
      let words = TextMatching.terms(in: passage)
      guard !words.isEmpty else {
        continue
      }
      let index = Int32(page.passages.count)
      page.passages.append(passage)
      page.lengths.append(Int32(words.count))
      page.totalLength += words.count
      var counts: [Int32: Int32] = [:]
      for word in words {
        counts[termID(word), default: 0] += 1
      }
      for (term, count) in counts {
        page.postings[term, default: []].append(
          Posting(passage: index, count: count))
        if passageFrequency[Int(term)] == 0 {
          liveTermCount += 1
        }
        passageFrequency[Int(term)] += 1
      }
    }
    guard !page.passages.isEmpty else {
      return
    }
    passageCount += page.passages.count
    totalLength += page.totalLength
    pages[tabID] = page
  }

  mutating func keepTabs(_ tabIDs: Set<Int>) {
    for tabID in pages.keys where !tabIDs.contains(tabID) {
      removePage(tabID)
    }
  }

  private mutating func removePage(_ tabID: Int) {
    guard let page = pages.removeValue(forKey: tabID) else {
      return
    }
    for (term, postings) in page.postings {
      passageFrequency[Int(term)] -= Int32(postings.count)
      if passageFrequency[Int(term)] == 0 {
        liveTermCount -= 1
      }
    }
    passageCount -= page.passages.count
    totalLength -= page.totalLength
    // Words of pages long gone would otherwise pile up.
    if terms.count > 50_000 + 2 * liveTermCount {
      compactTerms()
    }
  }

  private mutating func termID(_ term: String) -> Int32 {
    if let id = termIDs[term] {
      return id
    }
    let id = Int32(terms.count)
    let scalars = Array(term.unicodeScalars)
    terms.append(scalars)
    termIDs[term] = id
    passageFrequency.append(0)
    termsByFirstScalar[scalars[0], default: []].append(id)
    if scalars.contains(where: TextMatching.isUnspaced) {
      unspacedTerms.append(id)
    }
    return id
  }

  /// Renumbers the terms still in some page.
  private mutating func compactTerms() {
    var newIDs: [Int32] = Array(repeating: -1, count: terms.count)
    let oldTerms = terms
    let oldFrequency = passageFrequency
    terms = []
    termIDs = [:]
    passageFrequency = []
    termsByFirstScalar = [:]
    unspacedTerms = []
    for (old, scalars) in oldTerms.enumerated() where oldFrequency[old] > 0 {
      let id = termID(String(String.UnicodeScalarView(scalars)))
      passageFrequency[Int(id)] = oldFrequency[old]
      newIDs[old] = id
    }
    for (tabID, page) in pages {
      var postings: [Int32: [Posting]] = [:]
      for (term, list) in page.postings {
        postings[newIDs[Int(term)]] = list
      }
      pages[tabID]?.postings = postings
    }
  }

  /// `text` (a page's inner text, a line per block) as passages: lines
  /// gathered up to about `wordsPerPassage` words, and lines longer than that
  /// split.
  static func passages(of text: String) -> [String] {
    var passages: [String] = []
    var lines: [String] = []
    var lineWords = 0
    func flush() {
      if !lines.isEmpty {
        passages.append(lines.joined(separator: "\n"))
      }
      lines = []
      lineWords = 0
    }
    for rawLine in text.split(whereSeparator: \.isNewline) {
      let words = rawLine.split(whereSeparator: \.isWhitespace)
      let wordCount = words.count { word in
        word.unicodeScalars.contains(where: TextMatching.isWordScalar)
      }
      guard wordCount > 0 else {
        continue
      }
      if wordCount > wordsPerPassage * 3 / 2 {
        flush()
        var start = 0
        while start < words.count {
          let end = min(start + wordsPerPassage, words.count)
          passages.append(words[start..<end].joined(separator: " "))
          start = end
        }
        continue
      }
      if lineWords + wordCount > wordsPerPassage {
        flush()
      }
      lines.append(words.joined(separator: " "))
      lineWords += wordCount
    }
    flush()
    return passages
  }

  // MARK: Searching

  private typealias Expanded = [(term: Int32, weight: Double)]

  /// The tabs among `candidates` whose pages have, in one passage, the
  /// query's words each needs, best first.
  func search(
    _ query: PaletteQuery, in candidates: [PaletteSearch.PageTextCandidate]
  ) -> [PageTextMatch] {
    guard passageCount > 0 else {
      return []
    }
    let expansions = query.tokens.map(expand)
    let averageLength = Double(totalLength) / Double(passageCount)
    var matches: [PageTextMatch] = []
    for candidate in candidates {
      guard let page = pages[candidate.tabID], !candidate.required.isEmpty
      else {
        continue
      }
      var scores: [Int32: Double]?
      for token in candidate.required {
        let found = passageScores(
          expansions[token], in: page, averageLength: averageLength)
        if let current = scores {
          var both: [Int32: Double] = [:]
          for (passage, score) in current {
            if let more = found[passage] {
              both[passage] = score + more
            }
          }
          scores = both
        } else {
          scores = found
        }
        if scores!.isEmpty {
          break
        }
      }
      guard var scores, !scores.isEmpty else {
        continue
      }
      for token in candidate.optional {
        let found = passageScores(
          expansions[token], in: page, averageLength: averageLength)
        for (passage, score) in found where scores[passage] != nil {
          scores[passage]! += Weight.optional * score
        }
      }
      // The best few by words alone, then which has them side by side.
      let best = scores.sorted { $0.value > $1.value }.prefix(3).map {
        passage, score in
        let layout = layOut(
          page.passages[Int(passage)], expansions: expansions,
          required: candidate.required)
        return (
          passage: Int(passage),
          score: score * (1 + Weight.phrase * layout.phraseShare),
          layout: layout
        )
      }.max { $0.score < $1.score }!
      let find = findText(best.layout, in: page, passage: best.passage)
      matches.append(
        PageTextMatch(
          tabID: candidate.tabID,
          score: best.score * (1 + Weight.name * min(candidate.nameScore, 1)),
          snippet: best.layout.snippet, snippetRanges: best.layout.ranges,
          findText: find))
    }
    return Array(
      matches.sorted { $0.score > $1.score }.prefix(Self.resultLimit))
  }

  /// Each passage of `page` with one of `expansion`'s terms, scored for the
  /// best of them.
  private func passageScores(
    _ expansion: Expanded, in page: Page, averageLength: Double
  ) -> [Int32: Double] {
    var scores: [Int32: Double] = [:]
    for (term, weight) in expansion {
      guard let postings = page.postings[term] else {
        continue
      }
      let idf = inverseDocumentFrequency(term)
      for posting in postings {
        let count = Double(posting.count)
        let length = Double(page.lengths[Int(posting.passage)])
        let saturated =
          count * (BM25.k1 + 1)
          / (count + BM25.k1 * (1 - BM25.b + BM25.b * length / averageLength))
        let score = weight * idf * saturated
        scores[posting.passage] = max(scores[posting.passage] ?? 0, score)
      }
    }
    return scores
  }

  private func inverseDocumentFrequency(_ term: Int32) -> Double {
    let frequency = Double(passageFrequency[Int(term)])
    return log(1 + (Double(passageCount) - frequency + 0.5) / (frequency + 0.5))
  }

  /// The indexed terms `token` could mean: itself, words it starts, and words
  /// it's a likely typo of, each weighted for how sure that is.
  private func expand(_ token: PaletteQuery.Token) -> Expanded {
    let query = token.scalars
    var weights: [Int32: Double] = [:]
    func add(_ term: Int32, _ weight: Double) {
      weights[term] = max(weights[term] ?? 0, weight)
    }
    func isLive(_ term: Int32) -> Bool { passageFrequency[Int(term)] > 0 }
    if let term = termIDs[String(String.UnicodeScalarView(query))], isLive(term)
    {
      add(term, Weight.exact)
    }
    guard query.count >= 2 else {
      return Array(weights.map { ($0.key, $0.value) })
    }
    if token.isUnspaced {
      for term in unspacedTerms
        .lazy.filter({
          isLive($0)
            && TextMatching.firstIndex(of: query, in: self.terms[Int($0)])
              != nil
        }).prefix(Expansion.unspaced)
      {
        add(term, Weight.unspaced)
      }
    }
    let bucket = termsByFirstScalar[query[0]] ?? []
    let prefixed = bucket.filter {
      isLive($0) && terms[Int($0)].count > query.count
        && TextMatching.hasPrefix(terms[Int($0)], query)
    }
    for term in mostFrequent(prefixed, Expansion.prefixes) {
      add(term, token.isOpen ? Weight.openPrefix : Weight.prefix)
    }
    let limit = TextMatching.typoLimit(forLength: query.count)
    let known = weights.keys.reduce(0) { $0 + Int(passageFrequency[Int($1)]) }
    if limit > 0, known < Expansion.typoGate {
      var typos: [(term: Int32, distance: Int)] = []
      let swapped =
        query[1] != query[0] ? termsByFirstScalar[query[1]] ?? [] : []
      for term in bucket + swapped where isLive(term) {
        let scalars = terms[Int(term)]
        guard token.isOpen || abs(scalars.count - query.count) <= limit,
          TextMatching.couldBeTypo(query, of: scalars),
          let distance = TextMatching.editDistance(
            query, scalars, limit: limit, prefix: token.isOpen),
          distance > 0
        else {
          continue
        }
        typos.append((term, distance))
      }
      typos.sort {
        $0.distance != $1.distance
          ? $0.distance < $1.distance
          : passageFrequency[Int($0.term)] > passageFrequency[Int($1.term)]
      }
      for typo in typos.prefix(Expansion.typos) {
        add(typo.term, typo.distance <= 1 ? Weight.oneTypo : Weight.twoTypos)
      }
    }
    return Array(weights.map { ($0.key, $0.value) })
  }

  private func mostFrequent(_ candidates: [Int32], _ count: Int) -> [Int32] {
    guard candidates.count > count else {
      return candidates
    }
    return Array(
      candidates.sorted {
        passageFrequency[Int($0)] > passageFrequency[Int($1)]
      }.prefix(count))
  }

  // MARK: Snippets

  private static let snippetWords = 28
  /// Words shown before the first match.
  private static let snippetLead = 4

  private struct Layout {
    let words: [TextMatching.Word]
    /// For each word of the passage, the query word it matches.
    let tokens: [Int?]
    /// Of the query's pairs of neighboring words, the share side by side in
    /// the passage.
    let phraseShare: Double
    let snippet: String
    let ranges: [NSRange]
    /// The words the snippet shows, as indexes into `words`.
    let window: Range<Int>
  }

  /// Which of `passage`'s words match the query, and the snippet around the
  /// most of them.
  private func layOut(
    _ passage: String, expansions: [Expanded], required: [Int]
  ) -> Layout {
    let words = TextMatching.words(in: passage)
    guard !words.isEmpty else {
      return Layout(
        words: [], tokens: [], phraseShare: 0, snippet: passage, ranges: [],
        window: 0..<0)
    }
    let termSets = expansions.map { Set($0.map(\.term)) }
    let tokens: [Int?] = words.map { word in
      guard let term = termIDs[String(String.UnicodeScalarView(word.scalars))]
      else {
        return nil
      }
      return termSets.indices.first { termSets[$0].contains(term) }
    }
    var pairs = Set<Int>()
    for (a, b) in zip(tokens, tokens.dropFirst()) {
      if let a, let b, b == a + 1 {
        pairs.insert(a)
      }
    }
    let phraseShare =
      expansions.count > 1
      ? Double(pairs.count) / Double(expansions.count - 1) : 0

    // The window of words with the most of the query's words, earliest first.
    // It starts a few words before its first match, or where its line does.
    let text = passage as NSString
    let startsLine = words.indices.map {
      $0 == 0 || lineBreak(between: $0 - 1, and: $0, in: words, text: text)
    }
    let required = Set(required)
    var bestStart = 0
    var bestCover = (-1, -1)
    for (position, token) in tokens.enumerated() where token != nil {
      var start = position
      while start > 0, !startsLine[start], position - start < Self.snippetLead {
        start -= 1
      }
      let covered = Set(
        tokens[start..<min(start + Self.snippetWords, tokens.count)]
          .compactMap { $0 })
      let cover = (covered.intersection(required).count, covered.count)
      if cover > bestCover {
        bestCover = cover
        bestStart = start
      }
    }
    let window = bestStart..<min(bestStart + Self.snippetWords, words.count)

    // The window's words and what's between them, with line breaks as dots.
    var snippet = bestStart == 0 ? "" : "…"
    var ranges: [NSRange] = []
    func isSpace(_ index: Int) -> Bool {
      guard let scalar = Unicode.Scalar(text.character(at: index)) else {
        return false
      }
      return scalar.properties.isWhitespace
    }
    // Punctuation just before the first word, like "#" or "(".
    var leadStart = words[bestStart].range.location
    while leadStart > 0, !isSpace(leadStart - 1) {
      leadStart -= 1
    }
    snippet += text.substring(
      with: NSRange(
        location: leadStart, length: words[bestStart].range.location - leadStart
      ))
    for index in window {
      if index > bestStart {
        let gapStart = NSMaxRange(words[index - 1].range)
        let gap = text.substring(
          with: NSRange(
            location: gapStart, length: words[index].range.location - gapStart))
        if let newline = gap.firstIndex(of: "\n") {
          snippet += gap[..<newline] + " · "
        } else {
          snippet += gap
        }
      }
      let location = (snippet as NSString).length
      snippet += text.substring(with: words[index].range)
      if tokens[index] != nil {
        ranges.append(
          NSRange(location: location, length: words[index].range.length))
      }
    }
    // Punctuation just after the last word.
    var trailEnd = NSMaxRange(words[window.upperBound - 1].range)
    let trailStart = trailEnd
    while trailEnd < text.length, !isSpace(trailEnd),
      window.upperBound == words.count
        || trailEnd < words[window.upperBound].range.location
    {
      trailEnd += 1
    }
    snippet += text.substring(
      with: NSRange(location: trailStart, length: trailEnd - trailStart))
    if window.upperBound < words.count {
      snippet += "…"
    }
    return Layout(
      words: words, tokens: tokens, phraseShare: phraseShare,
      snippet: snippet, ranges: ranges, window: window)
  }

  /// Text that find in page will find the match by: the run of matched words
  /// in the snippet with the most of the query's, with words around it added
  /// (on the same line) until nothing else on the page has it.
  private func findText(_ layout: Layout, in page: Page, passage: Int) -> String
  {
    let text = page.passages[passage] as NSString
    let words = layout.words
    func isBreak(_ a: Int, _ b: Int) -> Bool {
      lineBreak(between: a, and: b, in: words, text: text)
    }
    var best: (first: Int, last: Int, tokens: Set<Int>)?
    var run: (first: Int, last: Int, tokens: Set<Int>)?
    for index in layout.window {
      guard let token = layout.tokens[index] else {
        run = nil
        continue
      }
      if let current = run, current.last == index - 1,
        !isBreak(current.last, index)
      {
        run = (current.first, index, current.tokens.union([token]))
      } else {
        run = (index, index, [token])
      }
      if run!.tokens.count > best?.tokens.count ?? 0 {
        best = run
      }
    }
    guard var (first, last, _) = best else {
      return ""
    }
    func phrase() -> String {
      let start = words[first].range.location
      return text.substring(
        with: NSRange(
          location: start, length: NSMaxRange(words[last].range) - start))
    }
    var growsRight = true
    for _ in 0..<8 where occurrences(of: phrase(), in: page) > 1 {
      let canGrowRight = last + 1 < words.count && !isBreak(last, last + 1)
      let canGrowLeft = first > 0 && !isBreak(first - 1, first)
      if canGrowRight && (growsRight || !canGrowLeft) {
        last += 1
      } else if canGrowLeft {
        first -= 1
      } else {
        break
      }
      growsRight.toggle()
    }
    return phrase()
  }

  private func lineBreak(
    between a: Int, and b: Int, in words: [TextMatching.Word], text: NSString
  ) -> Bool {
    let gapStart = NSMaxRange(words[a].range)
    let gap = NSRange(
      location: gapStart, length: words[b].range.location - gapStart)
    return text.range(of: "\n", options: [], range: gap).location != NSNotFound
  }

  private func occurrences(of phrase: String, in page: Page) -> Int {
    var count = 0
    for passage in page.passages where count < 2 {
      let text = passage as NSString
      var search = NSRange(location: 0, length: text.length)
      while count < 2 {
        let found = text.range(
          of: phrase, options: [.caseInsensitive, .diacriticInsensitive],
          range: search)
        guard found.location != NSNotFound else {
          break
        }
        count += 1
        let next = NSMaxRange(found)
        search = NSRange(location: next, length: text.length - next)
      }
    }
    return count
  }
}
