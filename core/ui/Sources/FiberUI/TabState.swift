import AppKit
import FiberBridge

@objc @implementation extension FiberTabState {
  let tabID: Int
  let title: String
  let favicon: NSImage?
  let isLoading: Bool

  @objc(initWithID:title:favicon:loading:)
  init(id tabID: Int, title: String, favicon: NSImage?, loading: Bool) {
    self.tabID = tabID
    self.title = title
    self.favicon = favicon
    self.isLoading = loading
    super.init()
  }
}
