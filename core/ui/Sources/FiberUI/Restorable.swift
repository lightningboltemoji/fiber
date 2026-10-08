import Foundation
import FiberBridge

@objc @implementation extension FiberRestorablePage {
  let title: String
  let url: String

  @objc(initWithTitle:url:)
  init(title: String, url: String) {
    self.title = title
    self.url = url
    super.init()
  }
}

@objc @implementation extension FiberRestorable {
  let restorableID: String
  let kind: FiberRestorableKind
  // Date's size isn't fixed across library versions, which @implementation's
  // stored properties need.
  private let nsDate: NSDate
  var date: Date { nsDate as Date }
  let windowCount: Int
  let pages: [FiberRestorablePage]

  @objc(initWithID:kind:date:windowCount:pages:)
  init(
    id restorableID: String, kind: FiberRestorableKind, date: Date,
    windowCount: Int, pages: [FiberRestorablePage]
  ) {
    self.restorableID = restorableID
    self.kind = kind
    self.nsDate = date as NSDate
    self.windowCount = windowCount
    self.pages = pages
    super.init()
  }
}
