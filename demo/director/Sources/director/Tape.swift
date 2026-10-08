import CoreGraphics
import Foundation

/// A demo script: settings for the take, then the steps played and recorded,
/// one command to a line. The commands are in .agents/DEMO.md.
struct Tape {
  var name: String
  var app: String?
  var window = CGSize(width: 1600, height: 1000)
  /// Pages loaded before the take, in a launch of their own, for history.
  var visits: [String] = []
  var pins: [(url: String, title: String)] = []
  /// The take's first window's tabs.
  var opens: [String] = []
  /// Where the pointer waits as the take starts, in window points.
  var pointer = CGPoint(x: -60, y: 600)
  var showsCursor = true
  var seed: UInt64 = 1
  var fps = 60
  /// Played before the take starts recording, to set the scene.
  var setup: [Step] = []
  var steps: [Step] = []
}

struct Step {
  var line: Int
  var text: String
  var command: Command
}

enum Command {
  case sleep(Duration)
  case type(String, perKey: Duration)
  case key([KeyCombo])
  case hold(KeyCombo, Duration)
  case move(Target, Duration)
  case click(Target?)
  case scroll(Double, Duration)
  case waitTitle(String, timeout: Duration)
  case waitElement(Target, gone: Bool, timeout: Duration)
  case waitLoad(timeout: Duration)
  case mark(String, Target)
  /// Prints the window's accessibility tree, for finding targets.
  case tree
}

/// What a step points at, resolved when the step runs.
enum Target: CustomStringConvertible {
  case window
  case point(CGPoint)
  case rect(CGRect)
  /// An element of the window's accessibility tree, by role and a label its
  /// title, description or value contains, the `index`th match.
  case element(role: String, label: String?, index: Int)
  /// An element of the active tab's page, by CSS selector.
  case page(String)

  /// Names for Fiber's own UI. The omnibar and command palette share a
  /// field and a list of results.
  static let aliases: [String: Target] = [
    "omnibar": .element(role: "AXTextField", label: nil, index: 0),
    "palette": .element(role: "AXTextField", label: nil, index: 0),
    "results": .element(role: "AXScrollArea", label: nil, index: 1),
    "picker": .element(role: "AXButton", label: "Tabs", index: 0),
    "overlay": .element(role: "AXGroup", label: "Tabs", index: 0),
    "pins": .element(role: "AXGroup", label: "Pinned", index: 0),
  ]

  var description: String {
    switch self {
    case .window: "window"
    case .point(let p): "@\(p.x),\(p.y)"
    case .rect(let r): "@\(r.minX),\(r.minY),\(r.width),\(r.height)"
    case .element(let role, let label, let index):
      "\(role)\(label.map { " \"\($0)\"" } ?? "")\(index > 0 ? " #\(index + 1)" : "")"
    case .page(let selector): "page \"\(selector)\""
    }
  }
}

struct TapeError: Error, CustomStringConvertible {
  var line: Int
  var message: String
  var description: String { "line \(line): \(message)" }
}

extension Tape {
  init(contentsOf url: URL) throws {
    self.init(name: url.deletingPathExtension().lastPathComponent)
    let lines = try String(contentsOf: url, encoding: .utf8)
      .components(separatedBy: .newlines)
    var recordLine: Int?
    for (offset, raw) in lines.enumerated() {
      let number = offset + 1
      var words = try Self.split(raw, line: number)
      guard !words.isEmpty else {
        continue
      }
      let name = words.removeFirst().lowercased()
      var parser = Parser(words: words, line: number)
      if name == "record" {
        if let recordLine {
          throw TapeError(line: number, message: "Record is already on line \(recordLine)")
        }
        recordLine = number
        setup = steps
        steps = []
      } else if try !applySetting(name, &parser) {
        let command = try parser.command(name)
        steps.append(Step(line: number, text: raw.trimmingCharacters(in: .whitespaces), command: command))
      }
      try parser.end()
    }
  }

  private mutating func applySetting(_ name: String, _ p: inout Parser) throws -> Bool {
    switch name {
    case "app": app = try p.word()
    case "window":
      let size = try p.word().split(separator: "x").compactMap { Double($0) }
      guard size.count == 2 else {
        throw p.error("Window takes WIDTHxHEIGHT")
      }
      window = CGSize(width: size[0], height: size[1])
    case "visit": visits += p.rest()
    case "pin": pins.append((try p.word(), try p.word()))
    case "open": opens += p.rest()
    case "pointer":
      guard case .point(let point) = try p.target() else {
        throw p.error("Pointer takes @X,Y")
      }
      pointer = point
    case "cursor": showsCursor = try p.word() != "hidden"
    case "seed": seed = UInt64(try p.number())
    case "fps": fps = Int(try p.number())
    default: return false
    }
    return true
  }

  /// Splits a line into words: quoted strings are one word, and `#` starts a
  /// comment at the start of a line or after a space.
  static func split(_ line: String, line number: Int) throws -> [String] {
    var words: [String] = []
    var word = ""
    var inWord = false
    var quoted = false
    var chars = Array(line)[...]
    while let c = chars.popFirst() {
      if quoted {
        if c == "\\", let next = chars.popFirst() {
          word.append(next)
        } else if c == "\"" {
          quoted = false
        } else {
          word.append(c)
        }
      } else if c == "\"" {
        quoted = true
        inWord = true
      } else if c == " " || c == "\t" {
        if inWord {
          words.append(word)
        }
        word = ""
        inWord = false
      } else if c == "#" && !inWord && (chars.first == " " || chars.isEmpty || words.isEmpty) {
        break
      } else {
        word.append(c)
        inWord = true
      }
    }
    if quoted {
      throw TapeError(line: number, message: "unterminated string")
    }
    if inWord {
      words.append(word)
    }
    return words
  }
}

private struct Parser {
  var words: [String]
  var line: Int
  var position = 0

  func error(_ message: String) -> TapeError {
    TapeError(line: line, message: message)
  }

  var atEnd: Bool { position == words.count }

  func peek() -> String? {
    atEnd ? nil : words[position]
  }

  mutating func word() throws -> String {
    guard let word = peek() else {
      throw error("expected more after \(words.joined(separator: " "))")
    }
    position += 1
    return word
  }

  mutating func rest() -> [String] {
    defer { position = words.count }
    return Array(words[position...])
  }

  mutating func number() throws -> Double {
    let word = try word()
    guard let value = Double(word) else {
      throw error("expected a number, not \(word)")
    }
    return value
  }

  /// `500ms`, `1.5s` or `2s`.
  mutating func duration() throws -> Duration {
    let word = try word()
    let (digits, scale): (Substring, Double) =
      word.hasSuffix("ms") ? (word.dropLast(2), 0.001) : word.hasSuffix("s") ? (word.dropLast(), 1) : ("", 0)
    guard let value = Double(digits) else {
      throw error("expected a duration like 500ms or 1.5s, not \(word)")
    }
    return .milliseconds(Int((value * scale * 1000).rounded()))
  }

  mutating func optionalDuration(_ fallback: Duration) throws -> Duration {
    guard let next = peek(), next.first?.isNumber == true else {
      return fallback
    }
    return try duration()
  }

  mutating func target() throws -> Target {
    let word = try word()
    if let alias = Target.aliases[word] {
      return alias
    }
    if word == "window" {
      return .window
    }
    if word == "page" {
      return .page(try self.word())
    }
    if word.hasPrefix("@") {
      let values = word.dropFirst().split(separator: ",").compactMap { Double($0) }
      switch values.count {
      case 2: return .point(CGPoint(x: values[0], y: values[1]))
      case 4: return .rect(CGRect(x: values[0], y: values[1], width: values[2], height: values[3]))
      default: throw error("expected @X,Y or @X,Y,W,H, not \(word)")
      }
    }
    if word.hasPrefix("AX") {
      var label: String?
      var index = 0
      if let next = peek(), !next.hasPrefix("#"), !next.first!.isNumber {
        label = try self.word()
      }
      if let next = peek(), next.hasPrefix("#"), let n = Int(next.dropFirst()) {
        position += 1
        index = n - 1
      }
      return .element(role: word, label: label, index: index)
    }
    throw error("unknown target \(word)")
  }

  mutating func command(_ name: String) throws -> Command {
    switch name {
    case "sleep":
      return .sleep(try duration())
    case "type":
      let text = try word()
      return .type(text, perKey: try optionalDuration(.milliseconds(85)))
    case "key":
      let combos = try rest().map { try KeyCombo(parsing: $0, line: line) }
      guard !combos.isEmpty else {
        throw error("Key takes at least one key")
      }
      return .key(combos)
    case "hold":
      return .hold(try KeyCombo(parsing: try word(), line: line), try duration())
    case "move":
      return .move(try target(), try optionalDuration(.milliseconds(700)))
    case "click":
      return .click(atEnd ? nil : try target())
    case "scroll":
      return .scroll(try number(), try optionalDuration(.milliseconds(1200)))
    case "wait":
      switch try word() {
      case "title":
        return .waitTitle(try word(), timeout: try optionalDuration(.seconds(10)))
      case "load":
        return .waitLoad(timeout: try optionalDuration(.seconds(10)))
      case "gone":
        return .waitElement(try target(), gone: true, timeout: try optionalDuration(.seconds(10)))
      default:
        position -= 1
        return .waitElement(try target(), gone: false, timeout: try optionalDuration(.seconds(10)))
      }
    case "mark":
      let name = try word()
      return .mark(name, atEnd ? .window : try target())
    case "tree":
      return .tree
    default:
      throw error("unknown command \(name)")
    }
  }

  func end() throws {
    if !atEnd {
      throw error("unexpected \(words[position...].joined(separator: " "))")
    }
  }
}
