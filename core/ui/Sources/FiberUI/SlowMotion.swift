import AppKit
import FiberBridge
import SwiftUI

@objc @implementation extension FiberSlowMotion {
  class var factor: Double {
    get { SlowMotion.factor }
    set { SlowMotion.factor = newValue }
  }
}

/// Animations played slower (see FiberSlowMotion). AppKit's and Core
/// Animation's follow each browser window's layer clock (`pace(_:)`), but
/// SwiftUI keeps its own: its animations take `slowMotion`.
@MainActor
enum SlowMotion {
  static var factor: Double = 1 {
    didSet {
      factor = max(factor, 1)
      for controller in BrowserWindowController.all {
        pace(controller.window)
      }
    }
  }

  /// For a delay that waits on an animation `duration` long.
  static func duration(_ duration: TimeInterval) -> TimeInterval {
    duration * factor
  }

  /// Sets `window`'s layer clock to `factor`, from where it is now.
  static func pace(_ window: NSWindow) {
    guard let content = window.contentView else {
      return
    }
    guard factor > 1 else {
      // Some of AppKit's animations start at the media time, so the clock
      // goes back to matching it rather than continuing.
      content.layer?.speed = 1
      content.layer?.timeOffset = 0
      content.layer?.beginTime = 0
      return
    }
    content.wantsLayer = true
    guard let layer = content.layer else {
      return
    }
    let now = CACurrentMediaTime()
    layer.timeOffset = layer.convertTime(now, from: nil)
    layer.beginTime = now
    layer.speed = Float(1 / factor)
  }
}

extension Animation {
  /// Played as slow as SlowMotion's factor makes it.
  @MainActor var slowMotion: Animation {
    SlowMotion.factor > 1 ? speed(1 / SlowMotion.factor) : self
  }
}
