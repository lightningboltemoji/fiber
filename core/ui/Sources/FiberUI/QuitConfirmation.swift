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
/// as the user holds the shortcut, and once they've held it long enough the
/// windows fade out. Letting go sooner lifts it again. A second press soon
/// after the first quits at once.
@MainActor
enum QuitHold {
  /// How long the user holds the shortcut to quit; the veil falls over it.
  private static let holdDuration: TimeInterval = 0.8
  /// A press this soon after the last one quits at once.
  private static let repeatInterval: TimeInterval = 1
  /// How often the loop checks on the key while waiting for it to go up.
  private static let pollInterval: TimeInterval = 0.1
  private static let fadeDuration: TimeInterval = 0.2
  private static let liftDuration: TimeInterval = 0.3
  /// A press older than this isn't happening now (see run(keyCode:…)).
  private static let staleEventAge: TimeInterval = 2

  private static var lastPress: Date?

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
    let now = Date()
    if let lastPress, now.timeIntervalSince(lastPress) < repeatInterval {
      // The windows go at once, and the quit waits for the key to go up:
      // held, it would repeat Command-Q into whichever app is active next.
      hideWindows(duration: 0)
      waitForKeyUp(keyCode: keyCode, deadline: nil)
      return true
    }
    lastPress = now

    for controller in BrowserWindowController.all {
      controller.setVeil(1, duration: holdDuration, timing: .easeIn)
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
      keyCode: keyCode, deadline: now.addingTimeInterval(holdDuration))
    if !held {
      for controller in BrowserWindowController.all {
        controller.setVeil(0, duration: liftDuration, timing: .easeOut)
      }
      // Any a quit had faded out, too.
      setWindowsAlpha(1, duration: liftDuration)
    }
    return held
  }

  /// Brings the windows back after a quit that didn't happen.
  static func restoreWindows() {
    // Lifted while they're out of sight.
    for controller in BrowserWindowController.all {
      controller.setVeil(0, duration: 0)
    }
    setWindowsAlpha(1, duration: fadeDuration)
  }

  /// Pumps key-ups until the key `keyCode` is up, fading the windows out if it
  /// stays down past `deadline`. Returns whether it did. The key's repeats
  /// and anything else that came in meanwhile are thrown away.
  @discardableResult
  private static func waitForKeyUp(keyCode: UInt16, deadline: Date?) -> Bool {
    var pastDeadline = false
    var lastEvent: NSEvent?
    repeat {
      lastEvent = NSApp.nextEvent(
        matching: .keyUp, until: Date(timeIntervalSinceNow: pollInterval),
        inMode: .eventTracking, dequeue: true)
      if let deadline, !pastDeadline, Date() >= deadline {
        pastDeadline = true
        hideWindows(duration: fadeDuration)
      }
    } while CGEventSource.keyState(
      .combinedSessionState, key: CGKeyCode(keyCode))
    NSApp.discardEvents(matching: .any, before: lastEvent)
    return pastDeadline
  }

  private static func hideWindows(duration: TimeInterval) {
    setWindowsAlpha(0, duration: duration)
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
