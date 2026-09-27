import AppKit
import FiberBridge

@objc @implementation extension FiberQuitConfirmation {
  @objc(runWithEvent:announcement:)
  class func run(with event: NSEvent, announcement: String) -> Bool {
    QuitHold.run(
      keyCode: event.keyCode, timestamp: event.timestamp,
      announcement: announcement)
  }

  class func restoreWindows() {
    QuitHold.restoreWindows()
  }
}

/// Holding Command-Q to quit. The veil falls over every browser window's page
/// as the user holds the shortcut, and drains back off it when they let go,
/// like a bucket: another press fills it from wherever it had drained to. Once
/// it's full the windows fade out.
@MainActor
enum QuitHold {
  /// How long the user holds the shortcut to fill the veil from empty.
  private static let holdDuration: TimeInterval = 0.65
  /// How long a full veil takes to drain once the user lets go.
  private static let drainDuration: TimeInterval = 1.6
  /// How often the loop checks on the key while waiting for it to go up.
  private static let pollInterval: TimeInterval = 0.1
  private static let fadeDuration: TimeInterval = 0.2
  /// A press older than this isn't happening now (see run(keyCode:…)).
  private static let staleEventAge: TimeInterval = 2

  /// How full the veil was when the user last let go, draining since
  /// `releaseDate`.
  private static var releasedLevel: CGFloat = 0
  private static var releaseDate = Date.distantPast

  /// How full the veil is at `date`, while the key's up.
  private static func level(at date: Date) -> CGFloat {
    let drained = date.timeIntervalSince(releaseDate) / drainDuration
    return max(0, releasedLevel - drained)
  }

  /// Runs until the key `keyCode` (the shortcut's) goes up, handling only
  /// key-ups meanwhile. Returns whether to quit.
  static func run(
    keyCode: UInt16, timestamp: TimeInterval, announcement: String
  ) -> Bool {
    // Only a press as it happens is held. A quit that comes later, while the
    // press is still the app's current event (one that waited for downloads,
    // say), goes ahead.
    if ProcessInfo.processInfo.systemUptime - timestamp > staleEventAge {
      return true
    }
    let pressDate = Date()
    let pressLevel = level(at: pressDate)
    let fillDuration = (1 - pressLevel) * holdDuration

    // Linear, filling and draining, so the veil shows the level.
    for controller in BrowserWindowController.all {
      controller.setVeil(1, duration: fillDuration, timing: .linear)
    }
    // VoiceOver says nothing on its own about why the app didn't quit.
    NSAccessibility.post(
      element: NSApp.mainWindow ?? NSApp as Any,
      notification: .announcementRequested,
      userInfo: [
        .announcement: announcement,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])

    let held = waitForKeyUp(
      keyCode: keyCode, deadline: pressDate.addingTimeInterval(fillDuration))
    if held {
      releasedLevel = 0
      return true
    }
    releaseDate = Date()
    releasedLevel = min(
      1, pressLevel + releaseDate.timeIntervalSince(pressDate) / holdDuration)
    for controller in BrowserWindowController.all {
      controller.setVeil(
        0, duration: releasedLevel * drainDuration, timing: .linear)
    }
    // Any a quit had faded out, too.
    setWindowsAlpha(1, duration: fadeDuration)
    return false
  }

  /// Brings the windows back after a quit that didn't happen.
  static func restoreWindows() {
    releasedLevel = 0
    // Lifted while they're out of sight.
    for controller in BrowserWindowController.all {
      controller.setVeil(0, duration: 0)
    }
    setWindowsAlpha(1, duration: fadeDuration)
  }

  /// Pumps key-ups until the key `keyCode` is up, fading the windows out if it
  /// stays down past `deadline`. Returns whether it did. The key's repeats
  /// and anything else that came in meanwhile are thrown away: held, it would
  /// repeat Command-Q into whichever app is active next.
  private static func waitForKeyUp(keyCode: UInt16, deadline: Date) -> Bool {
    var pastDeadline = false
    var lastEvent: NSEvent?
    repeat {
      lastEvent = NSApp.nextEvent(
        matching: .keyUp, until: Date(timeIntervalSinceNow: pollInterval),
        inMode: .eventTracking, dequeue: true)
      if !pastDeadline, Date() >= deadline {
        pastDeadline = true
        setWindowsAlpha(0, duration: fadeDuration)
      }
    } while CGEventSource.keyState(
      .combinedSessionState, key: CGKeyCode(keyCode))
    NSApp.discardEvents(matching: .any, before: lastEvent)
    return pastDeadline
  }

  /// The browser windows, and the sheets and other windows attached to them.
  private static func setWindowsAlpha(
    _ alpha: CGFloat, duration: TimeInterval
  ) {
    let windows = BrowserWindowController.all.flatMap { controller in
      let window = controller.window
      return [window] + (window.childWindows ?? [])
        + [window.attachedSheet].compactMap { $0 }
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      for window in windows {
        if duration > 0 {
          window.animator().alphaValue = alpha
        } else {
          window.alphaValue = alpha
        }
      }
    }
  }
}
