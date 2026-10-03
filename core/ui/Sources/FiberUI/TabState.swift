import AppKit
import FiberBridge

@objc @implementation extension FiberTabState {
  let tabID: Int
  let title: String
  let url: String
  let origin: String
  let favicon: NSImage?
  let isLoading: Bool
  // Date's size isn't fixed across library versions, which @implementation's
  // stored properties need.
  private let lastActiveDate: NSDate
  var lastActiveTime: Date { lastActiveDate as Date }

  @objc(initWithID:title:url:origin:favicon:loading:lastActiveTime:)
  init(
    id tabID: Int, title: String, url: String, origin: String,
    favicon: NSImage?, loading: Bool, lastActiveTime: Date
  ) {
    self.tabID = tabID
    self.title = title
    self.url = url
    self.origin = origin
    self.favicon = favicon
    self.isLoading = loading
    self.lastActiveDate = lastActiveTime as NSDate
    super.init()
  }
}
