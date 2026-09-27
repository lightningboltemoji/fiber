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

  @objc(leavePromptWithContent:site:window:actions:)
  class func leavePrompt(
    with content: FiberJavaScriptDialogContent, site: String, window: NSWindow,
    actions: any FiberJavaScriptDialogActions
  ) -> any FiberJavaScriptDialog {
    LeavePrompt(content: content, site: site, window: window, actions: actions)
  }
}

/// A page asking before it's left or reloaded (its beforeunload handler), asked
/// over the veiled page: "Leave site?", which site, and Leave (Return) or
/// Cancel (Escape). Chrome's text; pages can't give their own.
@MainActor
final class LeavePrompt: NSObject, FiberJavaScriptDialog {
  private let actions: any FiberJavaScriptDialogActions
  private weak var controller: BrowserWindowController?
  private var prompt: VeilPrompt?
  private var isDone = false

  init(
    content: FiberJavaScriptDialogContent, site: String, window: NSWindow,
    actions: any FiberJavaScriptDialogActions
  ) {
    self.actions = actions
    controller = BrowserWindowController.controller(for: window)
    super.init()
    let prompt = VeilPrompt(
      eyebrow: site, title: content.title, message: content.message,
      buttons: [
        .init(title: content.cancelButtonTitle, role: .cancel) {
          [weak self] in self?.finish { $0.dialogDidCancel() }
        },
        .init(title: content.acceptButtonTitle, role: .default) {
          [weak self] in self?.finish { $0.dialogDidAccept(withInput: "") }
        },
      ])
    self.prompt = prompt
    guard let controller else {
      // Nowhere to ask, so the answer is no; after returning, since the
      // answer can end the dialog's owner.
      DispatchQueue.main.async {
        self.finish { $0.dialogDidCancel() }
      }
      return
    }
    controller.present(prompt)
  }

  var userInput: String { "" }

  func close() {
    finish { $0.dialogDidDismiss() }
  }

  /// Takes the prompt down and reports how it ended, once.
  private func finish(_ report: (any FiberJavaScriptDialogActions) -> Void) {
    guard !isDone else {
      return
    }
    isDone = true
    if let prompt {
      controller?.dismiss(prompt)
    }
    report(actions)
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
