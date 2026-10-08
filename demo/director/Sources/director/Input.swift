import CoreGraphics
import Foundation

/// A key with modifiers, as a tape writes it: `cmd+shift+t`, `return`, `a`.
struct KeyCombo: CustomStringConvertible {
  var key: CGKeyCode
  var flags: CGEventFlags
  var text: String?
  var description: String

  init(parsing word: String, line: Int) throws {
    var parts = word.lowercased().split(separator: "+").map(String.init)
    guard let last = parts.popLast() else {
      throw TapeError(line: line, message: "empty key")
    }
    flags = []
    for part in parts {
      guard let modifier = Keyboard.modifiers[part] else {
        throw TapeError(line: line, message: "unknown modifier \(part)")
      }
      flags.insert(modifier.flag)
    }
    if let named = Keyboard.named[last] {
      key = named
    } else if last.count == 1, let (code, shift) = Keyboard.code(for: last.first!) {
      key = code
      text = last
      if shift {
        flags.insert(.maskShift)
      }
    } else {
      throw TapeError(line: line, message: "unknown key \(last)")
    }
    description = word
  }
}

/// US ANSI virtual key codes, which is what the events claim to come from.
enum Keyboard {
  static let modifiers: [String: (code: CGKeyCode, flag: CGEventFlags)] = [
    "cmd": (55, .maskCommand), "shift": (56, .maskShift),
    "option": (58, .maskAlternate), "opt": (58, .maskAlternate),
    "ctrl": (59, .maskControl), "control": (59, .maskControl),
  ]
  /// Pressed in this order and released in reverse, as hands do.
  static let modifierOrder: [(code: CGKeyCode, flag: CGEventFlags)] = [
    (59, .maskControl), (58, .maskAlternate), (56, .maskShift), (55, .maskCommand),
  ]

  static let named: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
    "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115, "end": 119,
    "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
  ]

  /// What each key code types, by code (NUL for keys that type nothing).
  private static let plain = Array("asdfhgzxcv\u{0}bqweryt123465=97-80]ou[ip\u{0}lj'k;\\,/nm.\u{0}\u{0}`")
  private static let shifted: [Character: Character] = [
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
    "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";",
    "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
  ]

  /// The key that types `c`, and whether it takes Shift. Characters off the
  /// keyboard (é, ã) come as `a`'s key carrying their text.
  static func code(for c: Character) -> (CGKeyCode, Bool)? {
    if c == " " {
      return (49, false)
    }
    if let base = shifted[c], let index = plain.firstIndex(of: base) {
      return (CGKeyCode(index), true)
    }
    if c.isUppercase, let index = plain.firstIndex(of: Character(c.lowercased())) {
      return (CGKeyCode(index), true)
    }
    if let index = plain.firstIndex(of: c), c != "\u{0}" {
      return (CGKeyCode(index), false)
    }
    return c.isLetter ? (0, false) : nil
  }
}

/// A deterministic random source, so a tape plays the same way every time.
struct SeededRandom: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed &+ 0x9E37_79B9_7F4A_7C15
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// Marks every event the director posts, which is how `InputWatch` tells
/// them from a person's.
let inputTag: Int64 = 0xF1_BE12

/// Real input, posted where the hardware's goes, so the app can't tell it
/// apart from a person's.
@MainActor
final class Input {
  private let source = CGEventSource(stateID: .hidSystemState)
  private var random: SeededRandom
  private var pressedModifiers: [(code: CGKeyCode, flag: CGEventFlags)] = []
  private var buttonDown = false
  /// Every pointer position posted, in global points.
  var onPointer: ((CGPoint, Bool) -> Void)?

  init(seed: UInt64) {
    random = SeededRandom(seed: seed)
  }

  var pointer: CGPoint {
    CGEvent(source: nil)?.location ?? .zero
  }

  private func post(_ event: CGEvent?) {
    guard let event else {
      return
    }
    event.setIntegerValueField(.eventSourceUserData, value: inputTag)
    event.post(tap: .cghidEventTap)
  }

  private func jitter(_ base: Double, by amount: Double) -> Duration {
    let ms = base * (1 + Double.random(in: -amount...amount, using: &random))
    return .microseconds(Int(ms * 1000))
  }

  // MARK: Keyboard

  private func keyEvent(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, text: String? = nil) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
    event?.flags = flags
    if let text {
      let units = Array(text.utf16)
      event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
    }
    post(event)
  }

  private func pressModifiers(_ flags: CGEventFlags) async {
    var held: CGEventFlags = []
    for modifier in Keyboard.modifierOrder where flags.contains(modifier.flag) {
      held.insert(modifier.flag)
      keyEvent(modifier.code, down: true, flags: held)
      pressedModifiers.append(modifier)
      try? await Task.sleep(for: jitter(28, by: 0.3))
    }
  }

  func releaseModifiers() async {
    var held = pressedModifiers.reduce(into: CGEventFlags()) { $0.insert($1.flag) }
    while let modifier = pressedModifiers.popLast() {
      held.remove(modifier.flag)
      keyEvent(modifier.code, down: false, flags: held)
      try? await Task.sleep(for: jitter(24, by: 0.3))
    }
  }

  /// Presses and lets go of `combo`, holding it `hold` long.
  func press(_ combo: KeyCombo, hold: Duration? = nil) async {
    await pressModifiers(combo.flags)
    keyEvent(combo.key, down: true, flags: combo.flags, text: combo.text)
    try? await Task.sleep(for: hold ?? jitter(70, by: 0.3))
    keyEvent(combo.key, down: false, flags: combo.flags, text: combo.text)
    try? await Task.sleep(for: jitter(30, by: 0.3))
    await releaseModifiers()
  }

  /// Types `text` a key at a time, `perKey` apart give or take, and a little
  /// slower after a space, as people type.
  func type(_ text: String, perKey: Duration) async {
    let base = perKey.seconds * 1000
    for c in text {
      guard let (code, shift) = Keyboard.code(for: c) else {
        continue
      }
      let flags: CGEventFlags = shift ? .maskShift : []
      if shift {
        await pressModifiers(.maskShift)
      }
      keyEvent(code, down: true, flags: flags, text: String(c))
      try? await Task.sleep(for: jitter(min(base * 0.55, 60), by: 0.25))
      keyEvent(code, down: false, flags: flags, text: String(c))
      if shift {
        await releaseModifiers()
      }
      try? await Task.sleep(for: jitter(c == " " ? base * 1.6 : base * 0.45, by: 0.35))
    }
  }

  // MARK: Pointer

  /// Moves the pointer to `target` along a slight arc, starting and stopping
  /// smoothly (minimum jerk), at 120 Hz.
  func move(to target: CGPoint, over duration: Duration) async {
    let start = pointer
    let distance = hypot(target.x - start.x, target.y - start.y)
    guard distance > 0.5 else {
      return
    }
    let bow = distance * Double.random(in: 0.04...0.12, using: &random) * (Bool.random(using: &random) ? 1 : -1)
    let mid = CGPoint(x: (start.x + target.x) / 2, y: (start.y + target.y) / 2)
    let control = CGPoint(
      x: mid.x - (target.y - start.y) / distance * bow,
      y: mid.y + (target.x - start.x) / distance * bow)
    let seconds = duration.seconds
    let clock = ContinuousClock()
    let began = clock.now
    var t = 0.0
    while t < 1 {
      try? await Task.sleep(until: began + .milliseconds(Int(t * seconds * 1000) + 8), clock: clock)
      t = min(1, (clock.now - began) / duration)
      let s = t * t * t * (10 - 15 * t + 6 * t * t)
      let u = 1 - s
      let point = CGPoint(
        x: u * u * start.x + 2 * u * s * control.x + s * s * target.x,
        y: u * u * start.y + 2 * u * s * control.y + s * s * target.y)
      warp(to: point)
    }
  }

  /// Puts the pointer at `point` at once.
  func warp(to point: CGPoint) {
    let type: CGEventType = buttonDown ? .leftMouseDragged : .mouseMoved
    post(CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left))
    onPointer?(point, buttonDown)
  }

  func click() async {
    let at = pointer
    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: at, mouseButton: .left)
    down?.setIntegerValueField(.mouseEventClickState, value: 1)
    post(down)
    buttonDown = true
    onPointer?(at, true)
    try? await Task.sleep(for: jitter(85, by: 0.25))
    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: at, mouseButton: .left)
    up?.setIntegerValueField(.mouseEventClickState, value: 1)
    post(up)
    buttonDown = false
    onPointer?(at, false)
  }

  /// Scrolls the page under the pointer `distance` points (down is positive)
  /// the way a trackpad does: pixel deltas in a gesture, easing out.
  func scroll(by distance: Double, over duration: Duration) async {
    let clock = ContinuousClock()
    let began = clock.now
    var done = 0.0
    var phase: Int64 = 1
    var t = 0.0
    while t < 1 {
      try? await Task.sleep(until: began + .milliseconds(Int(t * 1000 * duration.seconds) + 8), clock: clock)
      t = min(1, (clock.now - began) / duration)
      let eased = 1 - pow(1 - t, 3)
      let step = (distance * eased - done).rounded()
      done += step
      let event = CGEvent(
        scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: Int32(-step), wheel2: 0,
        wheel3: 0)
      event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
      event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: t >= 1 ? 4 : phase)
      post(event)
      phase = 2
    }
  }
}

extension Duration {
  var seconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
