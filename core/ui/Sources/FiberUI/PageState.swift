import FiberBridge
import Foundation

@objc @implementation extension FiberPageState {
  let displayURL: String
  let title: String
  let canGoBack: Bool
  let canGoForward: Bool
  let isLoading: Bool
  let isNewTabPage: Bool

  @objc(initWithDisplayURL:title:canGoBack:canGoForward:loading:newTabPage:)
  init(
    displayURL: String, title: String, canGoBack: Bool, canGoForward: Bool,
    loading: Bool, newTabPage: Bool
  ) {
    self.displayURL = displayURL
    self.title = title
    self.canGoBack = canGoBack
    self.canGoForward = canGoForward
    self.isLoading = loading
    self.isNewTabPage = newTabPage
    super.init()
  }
}
