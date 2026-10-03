import AppKit
import FiberBridge

/// Plays the part of Chrome's extensions for one window, with a few made-up
/// ones.
@MainActor
final class MockExtensions: NSObject, FiberExtensionsActions {
  private struct Mock {
    var id: String
    var name: String
    var symbol: String
    var color: NSColor
    var badge = ""
    var isEnabled = true
    var isPinned = false
    var popupSize = NSSize(width: 320, height: 220)
  }

  private let ui: any FiberExtensions
  private let window: NSWindow
  private var mocks: [Mock] = [
    Mock(
      id: "blocker", name: "Mock Blocker", symbol: "shield.lefthalf.filled",
      color: .systemRed, badge: "3", isPinned: true,
      popupSize: NSSize(width: 360, height: 280)),
    Mock(
      id: "notes", name: "Margin Notes", symbol: "note.text",
      color: .systemYellow),
    Mock(
      id: "dark", name: "Dark Reader (can't run here)",
      symbol: "moon.fill", color: .systemIndigo, isEnabled: false),
  ]
  private var popup: (any FiberExtensionPopup)?
  private var popupActions: PopupActions?
  private var windows: [MockExtensionWindow] = []
  private var prompt: (any FiberPrompt)?
  private var promptActions: PromptActions?
  private var countTimer: Timer?

  init(ui: any FiberExtensions, window: NSWindow) {
    self.ui = ui
    self.window = window
    super.init()
    ui.actions = self
    push()
    // Like a content blocker counting what it blocks.
    countTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.count() }
    }
  }

  func stop() {
    countTimer?.invalidate()
  }

  // MARK: FiberExtensionsActions

  func runExtension(withID extensionID: String, fromMenu: Bool) {
    guard let mock = mocks.first(where: { $0.id == extensionID }) else {
      return
    }
    guard mock.isEnabled else {
      ui.showMenuForExtension(withID: extensionID)
      return
    }
    ui.closeMenu()
    popup?.close()
    let actions = PopupActions { [weak self] in self?.popup = nil }
    let page = MockPopupPage(name: mock.name, color: mock.color) {
      [weak self] in
      // The page calling window.close().
      self?.popup?.close()
      self?.popup = nil
    }
    let popup = ui.popupForExtension(
      withID: extensionID, contentsView: page, actions: actions)
    popup.setContentSize(NSSize(width: 25, height: 25))
    self.popup = popup
    popupActions = actions
    // The page loads, then lays itself out.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak popup] in
      MainActor.assumeIsolated {
        popup?.setContentSize(mock.popupSize)
        popup?.show()
      }
    }
  }

  func setPinned(_ pinned: Bool, forExtensionWithID extensionID: String) {
    guard let index = mocks.firstIndex(where: { $0.id == extensionID }) else {
      return
    }
    mocks[index].isPinned = pinned
    push()
  }

  func showMenuForExtension(
    withID extensionID: String, event: NSEvent, view: NSView
  ) {
    guard let mock = mocks.first(where: { $0.id == extensionID }) else {
      return
    }
    let menu = ExtensionMenu { [weak self] choice in
      switch choice {
      case .pin: self?.setPinned(!mock.isPinned, forExtensionWithID: mock.id)
      case .remove: self?.remove(mock.id)
      case .options: print("Options for \(mock.name)")
      }
    }
    menu.show(for: mock.name, pinned: mock.isPinned, event: event, in: view)
  }

  func manageExtensions() {
    print("Manage Extensions")
  }

  /// What adding an extension from a store looks like: Fiber's prompt, then
  /// the one saying it was added.
  func simulateInstall() {
    let content = FiberPromptContent(
      icon: Self.icon("wand.and.stars", .systemTeal, size: 64), eyebrow: "",
      title: "Add \"Page Polisher\"?", message: "",
      listHeading: "It can:",
      listItems: [
        FiberPromptListItem(
          text: "Read and change all your data on all websites", detail: ""),
        FiberPromptListItem(
          text: "Read and change your data on a number of websites",
          detail: "example.com\nnews.example\nmail.example"),
        FiberPromptListItem(text: "Block content on any page", detail: ""),
      ],
      buttons: [
        FiberPromptButton(buttonID: 0, title: "Cancel", role: .cancel),
        FiberPromptButton(buttonID: 1, title: "Add extension", role: .confirm),
      ])
    showPrompt(content) { [weak self] button in
      guard button == 1 else {
        return
      }
      // The download and install take a moment.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        MainActor.assumeIsolated { self?.didInstall() }
      }
    }
  }

  /// What a password manager does to sign in: opens a window of its own.
  func openWindow() {
    let mock = mocks[windows.count % mocks.count]
    let window = MockExtensionWindow(
      ui: ui, name: mock.name, color: mock.color,
      icon: Self.icon(mock.symbol, mock.color, size: 32),
      site: windows.count % 2 == 1 ? "accounts.example.com" : ""
    ) { [weak self] closed in
      self?.windows.removeAll { $0 === closed }
    }
    windows.append(window)
  }

  // MARK: Private

  private func didInstall() {
    mocks.append(
      Mock(
        id: "polisher", name: "Page Polisher", symbol: "wand.and.stars",
        color: .systemTeal))
    push()
    let content = FiberPromptContent(
      icon: Self.icon("wand.and.stars", .systemTeal, size: 64), eyebrow: "",
      title: "Added “Page Polisher”",
      message: "Open it from the extensions menu, at the end of the toolbar.",
      listHeading: "", listItems: [],
      buttons: [
        FiberPromptButton(buttonID: 0, title: "Pin to Toolbar", role: .other),
        FiberPromptButton(buttonID: 1, title: "Done", role: .default),
      ])
    showPrompt(content) { [weak self] button in
      if button == 0 {
        self?.setPinned(true, forExtensionWithID: "polisher")
      }
    }
  }

  private func showPrompt(
    _ content: FiberPromptContent, then answered: @escaping (Int?) -> Void
  ) {
    let actions = PromptActions { [weak self] button in
      self?.prompt = nil
      answered(button)
    }
    promptActions = actions
    prompt = FiberPromptFactory.prompt(
      with: content, window: window, actions: actions)
  }

  private func remove(_ id: String) {
    mocks.removeAll { $0.id == id }
    push()
  }

  private func count() {
    guard let index = mocks.firstIndex(where: { $0.id == "blocker" }) else {
      return
    }
    let count = (Int(mocks[index].badge) ?? 0) + Int.random(in: 0...4)
    mocks[index].badge = count > 999 ? "999+" : String(count)
    push()
  }

  private func push() {
    let states = mocks.sorted { $0.name < $1.name }.map { mock in
      FiberExtensionState(
        extensionID: mock.id, name: mock.name,
        tooltip: mock.isEnabled ? mock.name : "\(mock.name) can't run here",
        icon: Self.icon(mock.symbol, mock.color, size: 16),
        badgeText: mock.badge, badgeTextColor: nil, badgeBackgroundColor: nil,
        enabled: mock.isEnabled, pinned: mock.isPinned, canTogglePin: true)
    }
    ui.setExtensions(
      states, pinnedIDs: mocks.filter(\.isPinned).map(\.id))
  }

  private static func icon(_ symbol: String, _ color: NSColor, size: CGFloat)
    -> NSImage?
  {
    NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size * 0.8, weight: .semibold)
          .applying(.init(paletteColors: [color])))
  }
}

@MainActor
private final class PopupActions: NSObject, FiberExtensionPopupActions {
  private let onClose: () -> Void

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose
  }

  func extensionPopupDidClose() {
    onClose()
  }
}

/// Forwards the button pressed, or nil if the prompt was dismissed.
@MainActor
final class PromptActions: NSObject, FiberPromptActions {
  private let onEnd: (Int?) -> Void

  init(onEnd: @escaping (Int?) -> Void) {
    self.onEnd = onEnd
  }

  func promptDidPressButton(withID buttonID: Int) {
    onEnd(buttonID)
  }

  func promptDidDismiss() {
    onEnd(nil)
  }
}

/// An extension's menu, as Chrome's would have it.
@MainActor
private final class ExtensionMenu: NSObject, FiberContextMenuActions {
  enum Choice: Int {
    case options, pin, remove
  }

  private let onChoose: (Choice) -> Void

  init(onChoose: @escaping (Choice) -> Void) {
    self.onChoose = onChoose
  }

  func show(for name: String, pinned: Bool, event: NSEvent, in view: NSView) {
    func item(_ choice: Choice, _ title: String) -> FiberContextMenuItem {
      FiberContextMenuItem(
        kind: .command, itemID: choice.rawValue, title: title,
        symbolName: nil, enabled: true, checked: false, submenu: [])
    }
    let items = [
      FiberContextMenuItem(
        kind: .command, itemID: -1, title: name, symbolName: nil,
        enabled: false, checked: false, submenu: []),
      FiberContextMenuItem(
        kind: .separator, itemID: -1, title: "", symbolName: nil,
        enabled: false, checked: false, submenu: []),
      item(.options, "Options"),
      item(.pin, pinned ? "Unpin" : "Pin"),
      item(.remove, "Remove from Fiber…"),
    ]
    FiberContextMenuFactory.menu(with: items, actions: self)
      .popUp(with: event, in: view)
  }

  func contextMenuWillOpen() {}

  func contextMenuDidClose() {}

  func contextMenuDidSelectItem(withID itemID: Int) {
    if let choice = Choice(rawValue: itemID) {
      onChoose(choice)
    }
  }
}

/// Stands in for an extension's popup page.
@MainActor
private final class MockPopupPage: NSView {
  private let onClose: () -> Void

  init(name: String, color: NSColor, onClose: @escaping () -> Void) {
    self.onClose = onClose
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    let title = NSTextField(labelWithString: name)
    title.font = .systemFont(ofSize: 17, weight: .semibold)
    title.textColor = color
    let toggle = NSButton(
      checkboxWithTitle: "Enabled on this site", target: nil, action: nil)
    toggle.state = .on
    let close = NSButton(
      title: "Close", target: self, action: #selector(closeClicked(_:)))
    let stack = NSStackView(views: [title, toggle, close])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  @objc private func closeClicked(_ sender: Any?) {
    onClose()
  }
}

/// Plays the part of an extension's window: its browser, and its page.
@MainActor
private final class MockExtensionWindow: NSObject, FiberExtensionWindowActions {
  // Set once `self` exists to be the bubble's actions.
  private var bubble: (any FiberExtensionWindow)!
  private let page: MockWindowPage
  private let onClose: (MockExtensionWindow) -> Void

  init(
    ui: any FiberExtensions, name: String, color: NSColor, icon: NSImage?,
    site: String, onClose: @escaping (MockExtensionWindow) -> Void
  ) {
    page = MockWindowPage(name: name, color: color)
    self.onClose = onClose
    super.init()
    page.onClose = { [weak self] in self?.close() }
    bubble = ui.extensionWindow(with: self)
    bubble.setTitle(name)
    bubble.setIcon(icon)
    bubble.setSite(site)
    bubble.setContentSize(NSSize(width: 380, height: 520))
    bubble.setContentsView(page)
    bubble.expand()
    focusPage()
  }

  // MARK: FiberExtensionWindowActions

  func extensionWindowShouldClose() {
    close()
  }

  func extensionWindowDidExpand() {
    focusPage()
  }

  func extensionWindowDidBecomeActive() {
    print("Active: \(page.name)'s window")
  }

  func extensionWindowDidResignActive() {
    print("Inactive: \(page.name)'s window")
  }

  // Command-W while its page has focus closes it, as closing its only tab
  // does in Chrome.
  @objc func closeTab(_ sender: Any?) {
    close()
  }

  // MARK: Private

  private func close() {
    bubble.close()
    onClose(self)
  }

  private func focusPage() {
    page.window?.makeFirstResponder(page.field)
  }
}

/// Stands in for an extension's own window's page, like a password manager's
/// sign-in.
@MainActor
private final class MockWindowPage: NSView {
  let name: String
  let field = NSTextField()
  var onClose: () -> Void = {}

  init(name: String, color: NSColor) {
    self.name = name
    super.init(frame: .zero)
    let title = NSTextField(labelWithString: "Sign in to \(name)")
    title.font = .systemFont(ofSize: 20, weight: .semibold)
    title.textColor = color
    field.placeholderString = "Email address"
    let password = NSSecureTextField()
    password.placeholderString = "Master password"
    let close = NSButton(
      title: "Close Window", target: self, action: #selector(closeClicked(_:)))
    let stack = NSStackView(views: [title, field, password, close])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
      field.widthAnchor.constraint(equalTo: stack.widthAnchor),
      password.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  @objc private func closeClicked(_ sender: Any?) {
    onClose()
  }
}
