import AppKit
import FiberBridge

@objc @implementation extension FiberPageState {
  let displayURL: String
  let title: String
  let canGoBack: Bool
  let canGoForward: Bool
  let isLoading: Bool
  let isNewTabPage: Bool
  let backgroundColor: NSColor?

  @objc(initWithDisplayURL:title:canGoBack:canGoForward:loading:newTabPage:backgroundColor:)
  init(
    displayURL: String, title: String, canGoBack: Bool, canGoForward: Bool,
    loading: Bool, newTabPage: Bool, backgroundColor: NSColor?
  ) {
    self.displayURL = displayURL
    self.title = title
    self.canGoBack = canGoBack
    self.canGoForward = canGoForward
    self.isLoading = loading
    self.isNewTabPage = newTabPage
    self.backgroundColor = backgroundColor
    super.init()
  }
}
