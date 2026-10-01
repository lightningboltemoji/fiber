import AppKit
import FiberBridge

@objc @implementation extension FiberDevTools {
  let view: NSView
  let dock: FiberDevToolsDock
  let pageFrame: NSRect
  let emulatesDevice: Bool

  init(
    view: NSView, dock: FiberDevToolsDock, pageFrame: NSRect,
    emulatesDevice: Bool
  ) {
    self.view = view
    self.dock = dock
    self.pageFrame = pageFrame
    self.emulatesDevice = emulatesDevice
    super.init()
  }
}
