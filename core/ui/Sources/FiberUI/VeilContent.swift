import AppKit

/// What a window waits on the user for, over its veil (see
/// BrowserWindowController.present(_:)). While it's up it has the window's
/// clicks, scrolls, keyboard focus and menu shortcuts, as a modal alert would.
@MainActor
protocol VeilContent: NSView {
  /// Called if it goes without being answered or dismissed by its owner:
  /// another took its place, or its window closed.
  var onRemoved: (() -> Void)? { get }
  /// What takes the keyboard focus when it's presented, if not itself.
  var initialFirstResponder: NSView? { get }
}
