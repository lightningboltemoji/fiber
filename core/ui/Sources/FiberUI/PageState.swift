import FiberBridge
import Foundation

@objc @implementation extension FiberPageState {
  @objc(URL) let url: String
  let displayURL: String
  let title: String
  let canGoBack: Bool
  let canGoForward: Bool
  let isLoading: Bool

  @objc(initWithURL:displayURL:title:canGoBack:canGoForward:loading:)
  init(
    url: String, displayURL: String, title: String, canGoBack: Bool,
    canGoForward: Bool, loading: Bool
  ) {
    self.url = url
    self.displayURL = displayURL
    self.title = title
    self.canGoBack = canGoBack
    self.canGoForward = canGoForward
    self.isLoading = loading
    super.init()
  }
}
