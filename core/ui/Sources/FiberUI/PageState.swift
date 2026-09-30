import FiberBridge
import Foundation

@objc @implementation extension FiberSadTab {
  let title: String
  let message: String
  let suggestions: [String]
  let errorCode: String
  let buttonTitle: String
  let helpTitle: String

  init(
    title: String, message: String, suggestions: [String], errorCode: String,
    buttonTitle: String, helpTitle: String
  ) {
    self.title = title
    self.message = message
    self.suggestions = suggestions
    self.errorCode = errorCode
    self.buttonTitle = buttonTitle
    self.helpTitle = helpTitle
    super.init()
  }
}

@objc @implementation extension FiberPageState {
  let displayURL: String
  let title: String
  let canGoBack: Bool
  let canGoForward: Bool
  let isLoading: Bool
  let isNewTabPage: Bool
  let sadTab: FiberSadTab?

  @objc(initWithDisplayURL:title:canGoBack:canGoForward:loading:newTabPage:sadTab:)
  init(
    displayURL: String, title: String, canGoBack: Bool, canGoForward: Bool,
    loading: Bool, newTabPage: Bool, sadTab: FiberSadTab?
  ) {
    self.displayURL = displayURL
    self.title = title
    self.canGoBack = canGoBack
    self.canGoForward = canGoForward
    self.isLoading = loading
    self.isNewTabPage = newTabPage
    self.sadTab = sadTab
    super.init()
  }
}
