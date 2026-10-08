import CoreGraphics
import Foundation

/// What happened in a take, and when, for the studio: the camera keys off its
/// markers and steps, and draws keys and the pointer from it. Times are
/// seconds from the take's first frame; places are window points, from the
/// top left.
struct Timeline: Encodable {
  struct Rect: Encodable {
    var x, y, width, height: Double
  }

  struct Marker: Encodable {
    var name: String
    var time: Double
    var rect: Rect
  }

  struct StepTime: Encodable {
    var line: Int
    var command: String
    var start: Double
    var end: Double
  }

  struct PointerSample: Encodable {
    var time: Double
    var x: Double
    var y: Double
    var pressed: Bool
  }

  struct KeyPress: Encodable {
    var time: Double
    var keys: String
  }

  var version = 1
  var tape: String
  var video = "take.mov"
  var mask = "window.png"
  var scale: Double
  var window: Rect
  var fps: Int
  var duration: Double = 0
  var markers: [Marker] = []
  var steps: [StepTime] = []
  var pointer: [PointerSample] = []
  var keys: [KeyPress] = []

  func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url)
  }
}

extension Timeline.Rect {
  init(_ rect: CGRect) {
    self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
  }
}
