import AppKit
import FiberBridge

@objc @implementation extension FiberPinState {
  let pinID: String
  let title: String
  let url: String
  let favicon: NSImage?
  let tabID: Int
  let isLoading: Bool
  let isAtPinnedURL: Bool

  @objc(initWithID:title:url:favicon:tabID:loading:atPinnedURL:)
  init(
    id pinID: String, title: String, url: String, favicon: NSImage?,
    tabID: Int, loading: Bool, atPinnedURL: Bool
  ) {
    self.pinID = pinID
    self.title = title
    self.url = url
    self.favicon = favicon
    self.tabID = tabID
    self.isLoading = loading
    self.isAtPinnedURL = atPinnedURL
    super.init()
  }
}
