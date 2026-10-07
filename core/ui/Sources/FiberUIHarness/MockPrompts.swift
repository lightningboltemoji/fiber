import AppKit
import FiberBridge

/// What //fiber/browser asks in a prompt, in Chrome's English, with the same
/// fields filled in as the builder named beside each, so the harness shows
/// what the app does.
enum PromptSample: String, CaseIterable {
  case location, camera, notifications, storageAccess, openApp, signIn
  case formResubmission, restoreFiles, leaveSite, addExtension
  case extensionAdded, removeExtension, nameWindow, downloads

  var label: String {
    switch self {
    case .location: "Location"
    case .camera: "Camera and Microphone"
    case .notifications: "Notifications"
    case .storageAccess: "Storage Access (two sites)"
    case .openApp: "Open in App"
    case .signIn: "Sign In (HTTP auth)"
    case .formResubmission: "Form Resubmission"
    case .restoreFiles: "Files From Last Visit"
    case .leaveSite: "Leave Site"
    case .addExtension: "Add Extension"
    case .extensionAdded: "Extension Added"
    case .removeExtension: "Remove Extension"
    case .nameWindow: "Name Window"
    case .downloads: "Downloads on Quit"
    }
  }

  /// The window's own, rather than a tab's.
  var isWindows: Bool {
    switch self {
    case .extensionAdded, .removeExtension, .nameWindow, .downloads: true
    default: false
    }
  }

  /// For the harness's `--prompt` flag.
  var flag: String { rawValue }

  /// What it asks on a page of `site`. Nil for the downloads, which aren't a
  /// FiberPrompt (see MockDownloads).
  @MainActor
  func content(site: String) -> FiberPromptContent? {
    switch self {
    case .location:
      // FiberPermissionPrompt
      permission(site, .location, "Know your location", canAllowThisTime: true)
    case .camera:
      permission(
        site, .camera, "Use your cameras", more: ["Use your microphones"],
        canAllowThisTime: true)
    case .notifications:
      permission(
        site, .notifications, "Show notifications", canAllowThisTime: false)
    case .storageAccess:
      // FiberPermissionPrompt, for a site embedded in the page.
      Self.content(
        topic: .storageAccess,
        title: "embed.example wants to use information they've saved about you",
        message: "embed.example will know that you visited \(site)",
        buttons: [
          FiberPromptButton(buttonID: 2, title: "Block", role: .other),
          FiberPromptButton(buttonID: 0, title: "Allow", role: .confirm),
        ])
    case .openApp:
      // ExternalProtocolPrompt
      Self.content(
        topic: .openApp, title: "Open Zoom?",
        message: "https://\(site) wants to open this application.",
        checkboxTitle:
          "Always allow \(site) to open links of this type in the associated app",
        buttons: [
          FiberPromptButton(buttonID: 1, title: "Cancel", role: .cancel),
          FiberPromptButton(buttonID: 0, title: "Open Zoom", role: .confirm),
        ])
    case .signIn:
      // FiberLoginHandler, for a page over HTTP.
      Self.content(
        topic: .signIn, title: "Sign in",
        message:
          "http://\(site) requires a username and password.\nYour connection to this site is not private",
        fields: [
          FiberPromptField(placeholder: "Username", text: "", kind: .username),
          FiberPromptField(placeholder: "Password", text: "", kind: .password),
        ],
        buttons: [
          FiberPromptButton(buttonID: 1, title: "Cancel", role: .cancel),
          FiberPromptButton(buttonID: 0, title: "Sign In", role: .default),
        ])
    case .formResubmission:
      // FiberTabModalConfirmDialog, for RepostFormWarningController.
      Self.content(
        topic: .general, title: "Confirm Form Resubmission",
        message:
          "The page that you're looking for used information that you entered. Returning to that page might cause any action you took to be repeated. Do you want to continue?",
        buttons: [
          FiberPromptButton(buttonID: 1, title: "Cancel", role: .cancel),
          FiberPromptButton(buttonID: 0, title: "Continue", role: .default),
        ])
    case .restoreFiles:
      // RestorePrompt
      Self.content(
        topic: .files, eyebrow: "\(site) wants to",
        title: "View and edit files from the last time you visited this site:",
        list: ["Budget 2026.numbers", "fiber"],
        buttons: [
          FiberPromptButton(buttonID: 2, title: "Don't allow", role: .other),
          FiberPromptButton(
            buttonID: 1, title: "Allow this time", role: .confirm),
          FiberPromptButton(
            buttonID: 0, title: "Allow on every visit", role: .confirm),
        ])
    case .leaveSite:
      // FiberAppModalDialogView, for a page's beforeunload handler.
      Self.content(
        topic: .leave, eyebrow: site, title: "Leave site?",
        message: "Changes you made may not be saved.",
        buttons: [
          FiberPromptButton(buttonID: 1, title: "Cancel", role: .cancel),
          FiberPromptButton(buttonID: 0, title: "Leave", role: .default),
        ])
    case .addExtension:
      // ExtensionInstallDialog
      Self.content(
        icon: Self.extensionIcon, topic: .extension,
        title: "Add \"Page Polisher\"?", listHeading: "It can:",
        listItems: [
          FiberPromptListItem(
            text: "Read and change all your data on all websites", detail: ""),
          FiberPromptListItem(
            text: "Read and change your data on a number of websites",
            detail: "example.com\nnews.example\nmail.example"),
          FiberPromptListItem(text: "Block content on any page", detail: ""),
        ],
        buttons: [
          FiberPromptButton(buttonID: 1, title: "Cancel", role: .cancel),
          FiberPromptButton(
            buttonID: 0, title: "Add extension", role: .confirm),
        ])
    case .extensionAdded:
      // ShowExtensionInstalled()
      Self.content(
        icon: Self.extensionIcon, topic: .extension,
        title: "Added “Page Polisher”",
        message: "Open it from the extensions menu, at the end of the toolbar.",
        buttons: [
          FiberPromptButton(buttonID: 2, title: "Pin to Toolbar", role: .other),
          FiberPromptButton(buttonID: 3, title: "Done", role: .default),
        ])
    case .removeExtension:
      Self.removeExtension(named: "Page Polisher", icon: Self.extensionIcon)
    case .nameWindow:
      // DialogModelPrompt, for Chrome's window name prompt.
      Self.content(
        topic: .general, title: "Name this window",
        fields: [
          FiberPromptField(placeholder: "Window name", text: "", kind: .text)
        ],
        buttons: [
          FiberPromptButton(buttonID: 1, title: "Cancel", role: .cancel),
          FiberPromptButton(buttonID: 0, title: "OK", role: .default),
        ])
    case .downloads:
      nil
    }
  }

  @MainActor
  private func permission(
    _ site: String, _ topic: FiberPromptTopic, _ title: String,
    more: [String] = [], canAllowThisTime: Bool
  ) -> FiberPromptContent {
    var buttons = [
      FiberPromptButton(
        buttonID: 2, title: canAllowThisTime ? "Never allow" : "Block",
        role: .other)
    ]
    if canAllowThisTime {
      buttons.append(
        FiberPromptButton(
          buttonID: 1, title: "Allow this time", role: .confirm))
    }
    buttons.append(
      FiberPromptButton(buttonID: 0, title: "Allow", role: .confirm))
    return Self.content(
      topic: topic, eyebrow: "\(site) wants to", title: title, list: more,
      buttons: buttons)
  }

  @MainActor
  private static func content(
    icon: NSImage? = nil, topic: FiberPromptTopic, eyebrow: String = "",
    title: String, message: String = "", list: [String] = [],
    listHeading: String = "", listItems: [FiberPromptListItem] = [],
    fields: [FiberPromptField] = [], checkboxTitle: String = "",
    buttons: [FiberPromptButton]
  ) -> FiberPromptContent {
    FiberPromptContent(
      icon: icon, topic: topic, eyebrow: eyebrow, title: title,
      message: message, listHeading: listHeading,
      listItems: listItems
        + list.map { FiberPromptListItem(text: $0, detail: "") },
      fields: fields, checkboxTitle: checkboxTitle, buttons: buttons)
  }

  /// FiberExtensionUninstallDialog's. Remove is button 0.
  @MainActor
  static func removeExtension(named name: String, icon: NSImage?)
    -> FiberPromptContent
  {
    content(
      icon: icon, topic: .extension, title: "Remove \"\(name)\"?",
      buttons: [
        FiberPromptButton(buttonID: 1, title: "Cancel", role: .cancel),
        FiberPromptButton(buttonID: 0, title: "Remove", role: .default),
      ])
  }

  /// Page Polisher's, as MockExtensions draws it.
  @MainActor
  static var extensionIcon: NSImage? {
    MockExtensions.icon("wand.and.stars", .systemTeal, size: 64)
  }
}
