import AppKit
import FiberBridge

@objc @implementation extension FiberPromptButton {
  let buttonID: Int
  let title: String
  let role: FiberPromptButtonRole

  init(buttonID: Int, title: String, role: FiberPromptButtonRole) {
    self.buttonID = buttonID
    self.title = title
    self.role = role
    super.init()
  }
}

@objc @implementation extension FiberPromptListItem {
  let text: String
  let detail: String

  init(text: String, detail: String) {
    self.text = text
    self.detail = detail
    super.init()
  }
}

@objc @implementation extension FiberPromptField {
  let placeholder: String
  let text: String
  let kind: FiberPromptFieldKind

  init(placeholder: String, text: String, kind: FiberPromptFieldKind) {
    self.placeholder = placeholder
    self.text = text
    self.kind = kind
    super.init()
  }
}

@objc @implementation extension FiberPromptContent {
  let icon: NSImage?
  let topic: FiberPromptTopic
  let eyebrow: String
  let title: String
  let message: String
  let listHeading: String
  let listItems: [FiberPromptListItem]
  let fields: [FiberPromptField]
  let checkboxTitle: String
  let buttons: [FiberPromptButton]

  convenience init(
    icon: NSImage?, topic: FiberPromptTopic, eyebrow: String, title: String,
    message: String, listHeading: String, listItems: [FiberPromptListItem],
    buttons: [FiberPromptButton]
  ) {
    self.init(
      icon: icon, topic: topic, eyebrow: eyebrow, title: title,
      message: message, listHeading: listHeading, listItems: listItems,
      fields: [], checkboxTitle: "", buttons: buttons)
  }

  init(
    icon: NSImage?, topic: FiberPromptTopic, eyebrow: String, title: String,
    message: String, listHeading: String, listItems: [FiberPromptListItem],
    fields: [FiberPromptField], checkboxTitle: String,
    buttons: [FiberPromptButton]
  ) {
    self.icon = icon
    self.topic = topic
    self.eyebrow = eyebrow
    self.title = title
    self.message = message
    self.listHeading = listHeading
    self.listItems = listItems
    self.fields = fields
    self.checkboxTitle = checkboxTitle
    self.buttons = buttons
    super.init()
  }
}

@objc @implementation extension FiberPromptFactory {
  @objc(promptWithContent:tabID:window:actions:)
  class func prompt(
    with content: FiberPromptContent, tabID: Int, window: NSWindow,
    actions: any FiberPromptActions
  ) -> any FiberPrompt {
    BubblePrompt(
      content: content, tabID: tabID, window: window, actions: actions)
  }

  @objc(promptWithContent:window:actions:)
  class func prompt(
    with content: FiberPromptContent, window: NSWindow,
    actions: any FiberPromptActions
  ) -> any FiberPrompt {
    BubblePrompt(content: content, tabID: nil, window: window, actions: actions)
  }
}
