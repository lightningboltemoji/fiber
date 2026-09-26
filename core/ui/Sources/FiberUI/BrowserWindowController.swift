import AppKit
import FiberBridge

@objc @implementation extension FiberWindowFactory {
  class func window(withFrame frame: NSRect, actions: any FiberWindowActions)
    -> any FiberWindow
  {
    BrowserWindowController(frame: frame, actions: actions)
  }
}

extension NSToolbarItem.Identifier {
  fileprivate static let back = Self("fiber.back")
  fileprivate static let forward = Self("fiber.forward")
  fileprivate static let reload = Self("fiber.reload")
  fileprivate static let location = Self("fiber.location")
}

/// A browser window and its native chrome: the toolbar, the load progress bar,
/// and the link status bubble. Reports what the user does to its actions.
@MainActor
final class BrowserWindowController: NSObject, FiberWindow {
  private static let defaultWindowSize = NSSize(width: 1280, height: 820)
  private static let minWindowSize = NSSize(width: 480, height: 320)
  private static let locationBarHeight: CGFloat = 36
  private static let progressBarHeight: CGFloat = 3
  // Inset from the window's bottom-left corner, clear of its rounding.
  private static let statusBubbleInset: CGFloat = 10

  var window: NSWindow { browserWindow }

  private let browserWindow: BrowserWindow
  private let actions: any FiberWindowActions
  private let backItem = NSToolbarItem(itemIdentifier: .back)
  private let forwardItem = NSToolbarItem(itemIdentifier: .forward)
  private let reloadItem = NSToolbarItem(itemIdentifier: .reload)
  private let locationItem = NSToolbarItem(itemIdentifier: .location)
  private let locationField = LocationField()
  private let progressBar = LoadProgressBar()
  private let statusBubble = StatusBubble()
  private weak var contentsView: NSView?
  private var isLoading = false

  init(frame: NSRect, actions: any FiberWindowActions) {
    self.actions = actions
    browserWindow = BrowserWindow(
      contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    super.init()

    let window = browserWindow
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.menuActionTarget = actions
    window.minSize = Self.minWindowSize
    window.title = "Fiber"
    // The page title is kept for the Window menu and Mission Control, but the
    // toolbar takes the title bar's place.
    window.titleVisibility = .hidden
    window.collectionBehavior.insert(.fullScreenPrimary)
    // Fiber will have its own tabs; keep AppKit from merging windows.
    window.tabbingMode = .disallowed

    configureToolbarItems()
    let toolbar = NSToolbar(identifier: "FiberWindowToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    toolbar.centeredItemIdentifiers = [.location]
    window.toolbar = toolbar
    window.toolbarStyle = .unified

    let content = window.contentView!
    progressBar.frame = NSRect(
      x: 0, y: content.bounds.height - Self.progressBarHeight,
      width: content.bounds.width, height: Self.progressBarHeight)
    progressBar.autoresizingMask = [.width, .minYMargin]
    content.addSubview(progressBar)

    statusBubble.setFrameOrigin(
      NSPoint(x: Self.statusBubbleInset, y: Self.statusBubbleInset))
    statusBubble.autoresizingMask = [.maxXMargin, .maxYMargin]
    content.addSubview(statusBubble)

    if frame.isEmpty {
      window.center()
    } else {
      window.setFrame(frame, display: false)
    }
  }

  private func configureToolbarItems() {
    configureButton(
      backItem, symbol: "chevron.backward", label: "Back",
      action: #selector(goBack(_:)))
    configureButton(
      forwardItem, symbol: "chevron.forward", label: "Forward",
      action: #selector(goForward(_:)))
    configureButton(
      reloadItem, symbol: "arrow.clockwise", label: "Reload",
      action: #selector(reloadOrStop(_:)))

    locationField.target = self
    locationField.action = #selector(navigateToLocation(_:))
    locationField.delegate = self

    // Toolbar items with custom views get no background of their own, so
    // match the Liquid Glass capsules of the standard items.
    let locationBar = NSGlassEffectView()
    locationBar.cornerRadius = Self.locationBarHeight / 2
    locationBar.contentView = locationField
    locationBar.heightAnchor.constraint(equalToConstant: Self.locationBarHeight)
      .isActive = true
    // Grow toward the max width, but let the toolbar squeeze it down to the
    // min.
    locationBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
      .isActive = true
    locationBar.widthAnchor.constraint(lessThanOrEqualToConstant: 800)
      .isActive = true
    let preferredWidth = locationBar.widthAnchor.constraint(
      equalToConstant: 800)
    preferredWidth.priority = .defaultLow
    preferredWidth.isActive = true

    locationItem.view = locationBar
    locationItem.label = "Address"
    locationItem.visibilityPriority = .high
  }

  private func configureButton(
    _ item: NSToolbarItem, symbol: String, label: String, action: Selector
  ) {
    item.image = NSImage(
      systemSymbolName: symbol, accessibilityDescription: label)
    item.label = label
    item.toolTip = label
    item.target = self
    item.action = action
    item.isBordered = true
    item.isNavigational = true
    // Enabled state is pushed by setPageState(_:), not polled.
    item.autovalidates = false
  }

  // MARK: FiberWindow

  func setContentsView(_ view: NSView?) {
    if view === contentsView {
      return
    }
    contentsView?.removeFromSuperview()
    contentsView = view
    guard let view, let content = window.contentView else {
      return
    }
    view.frame = content.bounds
    view.autoresizingMask = [.width, .height]
    // Below the progress bar and status bubble.
    content.addSubview(view, positioned: .below, relativeTo: nil)
  }

  func setPageState(_ state: FiberPageState) {
    window.title = state.title.isEmpty ? "Fiber" : state.title
    locationField.setURL(state.url, displayURL: state.displayURL)
    backItem.isEnabled = state.canGoBack
    forwardItem.isEnabled = state.canGoForward
    isLoading = state.isLoading
    let reloadLabel = isLoading ? "Stop" : "Reload"
    reloadItem.image = NSImage(
      systemSymbolName: isLoading ? "xmark" : "arrow.clockwise",
      accessibilityDescription: reloadLabel)
    reloadItem.label = reloadLabel
    reloadItem.toolTip = reloadLabel
  }

  func setLoading(_ loading: Bool, progress: Double) {
    if loading {
      progressBar.setProgress(progress)
    } else {
      progressBar.finish()
    }
  }

  func setStatusText(_ text: String) {
    statusBubble.setText(text)
  }

  func setToolbarVisible(_ visible: Bool) {
    window.toolbar?.isVisible = visible
  }

  func focusLocationBar() {
    if locationField.isEditing {
      locationField.currentEditor()?.selectAll(nil)
    } else {
      window.makeFirstResponder(locationField)
    }
  }

  // MARK: Toolbar actions

  // Each passes on the current event, whose modifier keys decide where the
  // page opens (e.g. Command-clicking Back opens it in a new tab).

  @objc private func goBack(_ sender: Any?) {
    actions.goBack(with: NSApp.currentEvent)
  }

  @objc private func goForward(_ sender: Any?) {
    actions.goForward(with: NSApp.currentEvent)
  }

  @objc private func reloadOrStop(_ sender: Any?) {
    if isLoading {
      actions.stopLoading()
    } else {
      actions.reload(with: NSApp.currentEvent)
    }
  }

  @objc private func navigateToLocation(_ sender: Any?) {
    actions.navigate(
      toInput: locationField.stringValue, event: NSApp.currentEvent)
  }
}

extension BrowserWindowController: NSToolbarDelegate {
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar)
    -> [NSToolbarItem.Identifier]
  {
    [.back, .forward, .reload, .location]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar)
    -> [NSToolbarItem.Identifier]
  {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier identifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    [backItem, forwardItem, reloadItem, locationItem].first {
      $0.itemIdentifier == identifier
    }
  }
}

extension BrowserWindowController: NSTextFieldDelegate {
  // Escape reverts the location field's edits; a second Escape returns focus
  // to the page.
  func control(
    _ control: NSControl, textView: NSTextView,
    doCommandBy selector: Selector
  ) -> Bool {
    guard control === locationField,
      selector == #selector(NSResponder.cancelOperation(_:))
    else {
      return false
    }
    if locationField.hasEdits {
      locationField.revertEdits()
    } else {
      actions.focusPage()
    }
    return true
  }
}

extension BrowserWindowController: NSWindowDelegate {
  // Closing goes through the browser, which runs unload handlers and closes
  // the tabs first; the window really closes when its owner is done with it.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    actions.windowShouldClose()
    return false
  }

  func windowDidBecomeMain(_ notification: Notification) {
    actions.windowDidBecomeMain()
  }

  func windowDidResignMain(_ notification: Notification) {
    actions.windowDidResignMain()
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    actions.windowDidChangeFullScreen()
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    actions.windowDidChangeFullScreen()
  }
}

/// Sends menu actions that nothing in the responder chain handles to the
/// window's actions, so the main menu acts on this window's browser while
/// it's key.
private final class BrowserWindow: NSWindow {
  weak var menuActionTarget: (any FiberWindowActions)?

  override func supplementalTarget(forAction action: Selector, sender: Any?)
    -> Any?
  {
    if let menuActionTarget, menuActionTarget.responds(to: action) {
      return menuActionTarget
    }
    return super.supplementalTarget(forAction: action, sender: sender)
  }
}
