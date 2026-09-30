import AppKit
import FiberBridge
import SwiftUI

@objc @implementation extension FiberProfile {
  let profileID: String
  let name: String
  let avatarIndex: Int
  let current: Bool

  init(profileID: String, name: String, avatarIndex: Int, current: Bool) {
    self.profileID = profileID
    self.name = name
    self.avatarIndex = avatarIndex
    self.current = current
    super.init()
  }
}

@objc @implementation extension FiberImportSource {
  let sourceID: Int
  let name: String
  let detail: String
  let avatarIndex: Int
  let picture: NSImage?

  init(
    sourceID: Int, name: String, detail: String, avatarIndex: Int,
    picture: NSImage?
  ) {
    self.sourceID = sourceID
    self.name = name
    self.detail = detail
    self.avatarIndex = avatarIndex
    self.picture = picture
    super.init()
  }
}

@objc @implementation extension FiberProfileSwitcherContent {
  let profiles: [FiberProfile]
  let newProfileAvatarIndex: Int
  let importBrowser: String
  let importIcon: NSImage?
  let importSources: [FiberImportSource]
  let page: FiberProfileSwitcherPage

  init(
    profiles: [FiberProfile], newProfileAvatarIndex: Int,
    importBrowser: String, importIcon: NSImage?,
    importSources: [FiberImportSource], page: FiberProfileSwitcherPage
  ) {
    self.profiles = profiles
    self.newProfileAvatarIndex = newProfileAvatarIndex
    self.importBrowser = importBrowser
    self.importIcon = importIcon
    self.importSources = importSources
    self.page = page
    super.init()
  }
}

@objc @implementation extension FiberProfileSwitcherFactory {
  @objc(switcherWithContent:window:actions:)
  class func switcher(
    with content: FiberProfileSwitcherContent, window: NSWindow,
    actions: any FiberProfileSwitcherActions
  ) -> any FiberProfileSwitcher {
    ProfileSwitcher(content: content, window: window, actions: actions)
  }
}

/// The browser's profiles, and making another, over the veiled page: its
/// content, in a ProfileSwitcherOverlay.
@MainActor
final class ProfileSwitcher: NSObject, FiberProfileSwitcher {
  /// Enough for the largest place an avatar shows, the New Profile page's.
  private static let avatarImageSize: CGFloat = 96

  private let actions: any FiberProfileSwitcherActions
  private weak var controller: BrowserWindowController?
  private let overlay = ProfileSwitcherOverlay()
  private let canImport: Bool
  private var isDone = false

  init(
    content: FiberProfileSwitcherContent, window: NSWindow,
    actions: any FiberProfileSwitcherActions
  ) {
    self.actions = actions
    controller = BrowserWindowController.controller(for: window)
    canImport = !content.importSources.isEmpty
    super.init()
    let model = overlay.model
    model.avatars = ProfileAvatar.choices.map {
      let avatar = ProfileAvatar(index: $0)
      return AvatarOption(
        id: $0, image: avatar.image(size: Self.avatarImageSize),
        label: avatar.label)
    }
    model.newProfileAvatarID = content.newProfileAvatarIndex
    model.importTitle = "Import from \(content.importBrowser)"
    model.importIcon = content.importIcon
    model.importSources = content.importSources.map {
      ImportSource(
        id: $0.sourceID, name: $0.name, detail: $0.detail,
        avatar: $0.picture
          ?? ProfileAvatar(index: $0.avatarIndex).image(
            size: Self.avatarImageSize))
    }
    model.importSourceID = model.importSources.first?.id
    setProfiles(content.profiles)

    model.onPick = { [weak self] id in self?.pick(id) }
    model.onDismiss = { [weak self] in self?.close() }
    model.onCreate = { [weak self] name, avatarID in
      guard let self else {
        return
      }
      self.actions.createProfile(
        withName: name,
        avatarIndex: avatarID ?? ProfileAvatar.placeholderIndex)
      self.close()
    }
    model.onImport = { [weak self] sourceID in
      self?.overlay.model.importState = .importing("Importing…")
      self?.actions.importSource(withID: sourceID)
    }
    overlay.onRemoved = { [weak self] in
      self?.finish(removing: false)
    }
    guard let controller, controller.canShowProfileSwitcher else {
      // Nowhere to show it; after returning, since closing can end the
      // switcher's owner.
      DispatchQueue.main.async {
        self.finish(removing: false)
      }
      return
    }
    controller.present(overlay)
    if content.page == .newProfile {
      model.show(.newProfile, animated: false)
    }
  }

  func setProfiles(_ profiles: [FiberProfile]) {
    var items = profiles.map {
      OrbitItem(
        id: .profile($0.profileID), title: $0.name,
        avatar: ProfileAvatar(index: $0.avatarIndex).image(
          size: Self.avatarImageSize),
        isCurrent: $0.current)
    }
    items.append(
      OrbitItem(id: .newProfile, title: "New Profile", symbolName: "plus"))
    if canImport {
      items.append(
        OrbitItem(
          id: .importProfile, title: "Import",
          symbolName: "square.and.arrow.down"))
    }
    let model = overlay.model
    model.items = items
    if let selectedID = model.selectedID,
      !items.contains(where: { $0.id == selectedID })
    {
      model.selectedID = nil
    }
  }

  func setImportProgress(_ step: String) {
    overlay.model.importState = .importing(step)
  }

  func setImportFailure(_ message: String) {
    overlay.model.importState = .failed(message)
  }

  func close() {
    finish(removing: true)
  }

  private func pick(_ id: OrbitItem.ID) {
    switch id {
    case .profile(let profileID):
      if !overlay.model.items.contains(where: { $0.id == id && $0.isCurrent }) {
        actions.switchToProfile(withID: profileID)
      }
      close()
    case .newProfile:
      overlay.model.show(.newProfile)
    case .importProfile:
      overlay.model.show(.importProfile)
    }
  }

  private func finish(removing: Bool) {
    guard !isDone else {
      return
    }
    isDone = true
    if removing {
      overlay.retract()
      controller?.dismiss(overlay)
    }
    actions.profileSwitcherDidClose()
  }
}

/// The profiles, and ways to add one, on a ring turning slowly around a hub,
/// over the veiled page. The ring stops while the pointer is on an item or
/// one is chosen with the keyboard. ProfileSwitcherView draws it.
@MainActor
final class ProfileSwitcherOverlay: NSView, VeilContent {
  /// How quickly the ring comes to a stop, or back up to speed: the time
  /// constant of its easing, in seconds.
  private static let holdEasing: TimeInterval = 0.25

  let model = ProfileSwitcherModel()
  var onRemoved: (() -> Void)?
  var initialFirstResponder: NSView? { nil }

  private let hostingView: NSHostingView<ProfileSwitcherView>
  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval?
  /// Radians per second, clockwise.
  private var speed: Double = 0

  private static var cruisingSpeed: Double {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? 0 : 2 * .pi / OrbitLayout.period
  }

  override init(frame: NSRect) {
    hostingView = NSHostingView(rootView: ProfileSwitcherView(model: model))
    super.init(frame: frame)
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    model.size = bounds.size
    speed = Self.cruisingSpeed
    model.onPageChange = { [weak self] page in
      // The New Profile page focuses its name field itself.
      if page != .newProfile, let self {
        self.window?.makeFirstResponder(self)
      }
    }

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Profiles")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    model.size = newSize
  }

  /// Draws the items back into the hub, for the switcher going away.
  func retract() {
    model.closedAt = model.time
  }

  // MARK: Motion

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    displayLink?.invalidate()
    displayLink = nil
    lastTimestamp = nil
    guard let window else {
      return
    }
    let link = window.displayLink(target: self, selector: #selector(step(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func step(_ link: CADisplayLink) {
    let now = link.targetTimestamp
    let elapsed = now - (lastTimestamp ?? now)
    lastTimestamp = now
    let target = model.isHeld ? 0 : Self.cruisingSpeed
    speed += (target - speed) * (1 - exp(-elapsed / Self.holdEasing))
    model.turn += speed * elapsed
    model.time = now
    if model.openedAt == nil {
      model.openedAt = now
    }
  }

  // MARK: Keyboard

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    switch (model.page, event.keyCode) {
    case (_, 53):  // Escape
      cancelOperation(nil)
    case (.importProfile, 36), (.importProfile, 76):  // Return, Enter
      model.startImport()
    case (.orbit, _):
      orbitKeyDown(with: event)
    default:
      super.keyDown(with: event)
    }
  }

  private func orbitKeyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76, 49:  // Return, Enter, Space
      if let selectedID = model.selectedID {
        model.onPick(selectedID)
      }
    case 124, 125:  // Right, Down
      moveSelection(by: 1)
    case 123, 126:  // Left, Up
      moveSelection(by: -1)
    case 48:  // Tab
      moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
    default:
      selectProfile(startingWith: event.charactersIgnoringModifiers ?? "")
    }
  }

  override func cancelOperation(_ sender: Any?) {
    if model.page == .orbit {
      model.onDismiss()
    } else {
      model.show(.orbit)
    }
  }

  /// Clockwise for a positive `step`. The first press chooses the item at the
  /// top, or nearest it.
  private func moveSelection(by step: Int) {
    let items = model.items
    guard !items.isEmpty else {
      return
    }
    guard let selectedID = model.selectedID,
      let index = items.firstIndex(where: { $0.id == selectedID })
    else {
      model.selectedID = items[indexNearestTop()].id
      return
    }
    let next = (index + step + items.count) % items.count
    model.selectedID = items[next].id
  }

  private func indexNearestTop() -> Int {
    let count = Double(model.items.count)
    let turns = model.turn / (2 * .pi)
    // Item i is at the top when turn + 2πi/count is a whole turn.
    let index = Int((-turns * count).rounded())
    return ((index % model.items.count) + model.items.count) % model.items.count
  }

  private func selectProfile(startingWith prefix: String) {
    guard !prefix.isEmpty,
      let item = model.items.first(where: {
        if case .profile = $0.id {
          return $0.title.lowercased().hasPrefix(prefix.lowercased())
        }
        return false
      })
    else {
      return
    }
    model.selectedID = item.id
  }

  /// The menu's shortcuts wait until the switcher is gone, but for editing
  /// the text in its fields.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let editor = window?.firstResponder as? NSText,
      editor.isDescendant(of: self),
      let action = VeilPrompt.editingAction(for: event)
    {
      NSApp.sendAction(action, to: nil, from: self)
    }
    return true
  }

  // It covers the window, so scrolls and clicks outside the SwiftUI view's
  // buttons stop here, out of the page's reach.
  override func rightMouseDown(with event: NSEvent) {}
  override func otherMouseDown(with event: NSEvent) {}
  override func scrollWheel(with event: NSEvent) {}
}
