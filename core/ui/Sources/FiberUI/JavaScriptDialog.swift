import AppKit
import FiberBridge

@objc @implementation extension FiberJavaScriptDialogContent {
  let kind: FiberJavaScriptDialogKind
  let title: String
  let message: String
  let defaultPromptText: String
  let acceptButtonTitle: String
  let cancelButtonTitle: String

  init(
    kind: FiberJavaScriptDialogKind, title: String, message: String,
    defaultPromptText: String, acceptButtonTitle: String,
    cancelButtonTitle: String
  ) {
    self.kind = kind
    self.title = title
    self.message = message
    self.defaultPromptText = defaultPromptText
    self.acceptButtonTitle = acceptButtonTitle
    self.cancelButtonTitle = cancelButtonTitle
    super.init()
  }
}

@objc @implementation extension FiberJavaScriptDialogFactory {
  @objc(dialogWithContent:window:actions:)
  class func dialog(
    with content: FiberJavaScriptDialogContent, window: NSWindow,
    actions: any FiberJavaScriptDialogActions
  ) -> any FiberJavaScriptDialog {
    JavaScriptDialog(content: content, window: window, actions: actions)
  }
}

/// A JavaScript dialog, shown as an alert sheet on the page's window.
@MainActor
final class JavaScriptDialog: NSObject, FiberJavaScriptDialog {
  private static let promptFieldWidth: CGFloat = 280

  private let alert = NSAlert()
  private let promptField: NSTextField?
  private let actions: any FiberJavaScriptDialogActions
  private weak var window: NSWindow?

  init(
    content: FiberJavaScriptDialogContent, window: NSWindow,
    actions: any FiberJavaScriptDialogActions
  ) {
    self.actions = actions
    self.window = window
    alert.messageText = content.title
    alert.informativeText = content.message
    alert.addButton(withTitle: content.acceptButtonTitle)
    if content.kind != .alert {
      alert.addButton(withTitle: content.cancelButtonTitle)
    }
    if content.kind == .prompt {
      let field = NSTextField(string: content.defaultPromptText)
      field.setFrameSize(
        NSSize(width: Self.promptFieldWidth, height: field.fittingSize.height))
      alert.accessoryView = field
      promptField = field
    } else {
      promptField = nil
    }
    super.init()

    // The completion handler always runs, and keeps the dialog alive until
    // then.
    alert.beginSheetModal(for: window) { response in
      self.sheetDidEnd(with: response)
    }
    if let promptField {
      alert.window.makeFirstResponder(promptField)
    }
  }

  var userInput: String { promptField?.stringValue ?? "" }

  func close() {
    window?.endSheet(alert.window)
  }

  private func sheetDidEnd(with response: NSApplication.ModalResponse) {
    switch response {
    case .abort, .stop:
      // Ended by something other than the user: close(), or the window going
      // away.
      actions.dialogDidDismiss()
    case .alertFirstButtonReturn:
      actions.dialogDidAccept(withInput: userInput)
    default:
      actions.dialogDidCancel()
    }
  }
}
