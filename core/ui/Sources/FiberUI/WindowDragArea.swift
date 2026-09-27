import AppKit

/// Drags the window, like the title bar it sits in.
class WindowDragArea: NSView {
  override var mouseDownCanMoveWindow: Bool { true }

  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}
