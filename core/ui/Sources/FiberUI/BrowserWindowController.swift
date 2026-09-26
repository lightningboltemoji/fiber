import AppKit
import FiberBridge

@objc @implementation extension FiberWindowFactory {
  class func window(withFrame frame: NSRect, actions: any FiberWindowActions)
    -> any FiberWindow
  {
    BrowserWindowController(frame: frame, actions: actions)
  }
}

/// A browser window and its native chrome, all floating over the page: the
/// toolbar (shown with Command-S), the tab picker on the right edge, the
/// command palette (Command-L), the load
/// progress bar, and the link status bubble. Reports what the user does to its
/// actions.
@MainActor
final class BrowserWindowController: NSObject, FiberWindow {
  private static let defaultWindowSize = NSSize(width: 1280, height: 820)
  private static let minWindowSize = NSSize(width: 480, height: 320)
  /// How far the toolbar and the traffic lights' capsule float from the
  /// window's edges.
  fileprivate static let edgeInset: CGFloat = 16
  /// The glass capsule behind the traffic lights extends this far past them,
  /// rim included.
  fileprivate static let windowControlsPadding = NSSize(width: 14, height: 13)
  private static let windowControlsRimWidth: CGFloat = 5
  /// Where the traffic lights go: their capsule's top-left corner sits
  /// `edgeInset` from the window's.
  fileprivate static let windowControlsLayout = WindowFrame.Layout(
    buttonsInset: edgeInset + windowControlsPadding.width,
    // The traffic lights are 14pt, centered in the title bar.
    titlebarHeight: 2 * (edgeInset + windowControlsPadding.height) + 14)
  private static let progressBarHeight: CGFloat = 3
  // Inset from the window's bottom-left corner, clear of its rounding.
  private static let statusBubbleInset: CGFloat = 10

  var window: NSWindow { browserWindow }

  private let browserWindow: BrowserWindow
  private let actions: any FiberWindowActions
  private let toolbar = Toolbar()
  private let tabPicker = TabPicker()
  private let commandPalette = CommandPalette()
  private let newTabView = NewTabView()
  /// Whether the active tab is Chrome's New Tab page, which `newTabView`
  /// stands in for.
  private var isNewTabPage = false
  /// The page's full URL, which the command palette opens with.
  private var pageURL = ""
  private let progressBar = LoadProgressBar()
  private let statusBubble = StatusBubble()
  private let windowControlsBackground = RimmedGlassView(
    rimWidth: BrowserWindowController.windowControlsRimWidth)
  /// Shown with Command-S, until hidden with it again.
  private var isToolbarShown = false
  /// The toolbar and tab picker hide while a page is fullscreen.
  private var areControlsVisible = true
  fileprivate var isToolbarVisible: Bool {
    isToolbarShown && areControlsVisible
  }
  private weak var contentsView: NSView?
  private var isLoading = false

  init(frame: NSRect, actions: any FiberWindowActions) {
    self.actions = actions
    browserWindow = BrowserWindow(
      contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
      styleMask: [
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
      ],
      backing: .buffered,
      defer: false)
    super.init()

    let window = browserWindow
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.controller = self
    window.menuActionTarget = actions
    window.minSize = Self.minWindowSize
    window.title = "Fiber"
    // The page fills the window, title bar area included, with the traffic
    // lights over it. The page title is kept for the Window menu and Mission
    // Control.
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    // BrowserWindow moves the traffic lights in from the corner (see
    // windowControlsLayout). Pages under the title bar still get clicks
    // there, and don't move the window
    // (patches/chromium/content-app_shim_remote_cocoa-…); only the capsules
    // do.
    window.collectionBehavior.insert(.fullScreenPrimary)
    // Fiber has its own tabs; keep AppKit from merging windows.
    window.tabbingMode = .disallowed

    let content = window.contentView!
    // Just above the page (see setContentsView(_:)).
    newTabView.frame = content.bounds
    newTabView.autoresizingMask = [.width, .height]
    newTabView.isHidden = true
    newTabView.onClick = { [weak self] in self?.showCommandPalette() }
    content.addSubview(newTabView)

    progressBar.frame = NSRect(
      x: 0, y: content.bounds.height - Self.progressBarHeight,
      width: content.bounds.width, height: Self.progressBarHeight)
    progressBar.autoresizingMask = [.width, .minYMargin]
    content.addSubview(progressBar)

    statusBubble.setFrameOrigin(
      NSPoint(x: Self.statusBubbleInset, y: Self.statusBubbleInset))
    statusBubble.autoresizingMask = [.maxXMargin, .maxYMargin]
    content.addSubview(statusBubble)

    configureWindowControls()

    // Level with the traffic lights' capsule, and past it.
    configureToolbar()
    let controls = windowControlsBackground.frame
    let toolbarX = controls.maxX + Toolbar.spacing
    toolbar.frame = NSRect(
      x: toolbarX, y: content.bounds.height - Self.edgeInset - Toolbar.height,
      width: content.bounds.width - toolbarX - Self.edgeInset,
      height: Toolbar.height)
    toolbar.autoresizingMask = [.width, .minYMargin]
    content.addSubview(toolbar)
    updateToolbar(animated: false)

    tabPicker.frame = NSRect(
      x: content.bounds.width - TabPicker.width, y: 0, width: TabPicker.width,
      height: content.bounds.height)
    tabPicker.autoresizingMask = [.height, .minXMargin]
    tabPicker.onSelect = { [weak self] tabID in
      self?.actions.selectTab(withID: tabID)
    }
    content.addSubview(tabPicker)

    // Over everything.
    commandPalette.frame = content.bounds
    commandPalette.autoresizingMask = [.width, .height]
    commandPalette.onSubmit = { [weak self] input, event in
      self?.actions.navigate(toInput: input, event: event)
      self?.closeCommandPalette()
    }
    commandPalette.onDismiss = { [weak self] in self?.closeCommandPalette() }
    content.addSubview(commandPalette)

    if frame.isEmpty {
      window.center()
    } else {
      window.setFrame(frame, display: false)
    }
  }

  private func configureToolbar() {
    configureButton(toolbar.backButton, action: #selector(goBack(_:)))
    configureButton(toolbar.forwardButton, action: #selector(goForward(_:)))
    configureButton(toolbar.reloadButton, action: #selector(reloadOrStop(_:)))

    toolbar.addressButton.target = self
    toolbar.addressButton.action = #selector(addressClicked(_:))
  }

  /// Shows or hides the toolbar (Command-S).
  fileprivate func toggleToolbar() {
    isToolbarShown = !isToolbarVisible
    updateToolbar(animated: true)
  }

  /// Fades the toolbar in or out, with the traffic lights, which show with it.
  private func updateToolbar(animated: Bool) {
    let isVisible = isToolbarVisible
    if isVisible {
      toolbar.isHidden = false
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated ? (isVisible ? 0.18 : 0.25) : 0
      toolbar.animator().alphaValue = isVisible ? 1 : 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        // Hidden, so its controls don't take clicks or focus.
        if let self, !self.isToolbarVisible {
          self.toolbar.isHidden = true
        }
      }
    }
    updateWindowControls(animated: animated)
  }

  private var windowControlButtons: [NSButton] {
    [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
      .compactMap { window.standardWindowButton($0) }
  }

  /// Puts a glass capsule behind the traffic lights, which stay in the title
  /// bar above it. Dragging the capsule moves the window.
  private func configureWindowControls() {
    guard let content = window.contentView else {
      return
    }
    // Where AppKit put the traffic lights. The content view fills the window,
    // so window coordinates are the content view's.
    window.layoutIfNeeded()
    let buttonsFrame = windowControlButtons.reduce(NSRect.null) {
      $0.union($1.convert($1.bounds, to: nil))
    }
    guard !buttonsFrame.isNull else {
      return
    }
    let frame = buttonsFrame.insetBy(
      dx: -Self.windowControlsPadding.width,
      dy: -Self.windowControlsPadding.height)
    windowControlsBackground.frame = frame
    windowControlsBackground.cornerRadius = frame.height / 2
    windowControlsBackground.contentView = WindowDragArea()
    windowControlsBackground.autoresizingMask = [.maxXMargin, .minYMargin]
    content.addSubview(windowControlsBackground)
  }

  /// Shows the traffic lights and their capsule with the toolbar, and fades
  /// them out otherwise so the page shows through. While the window is
  /// fullscreen, AppKit shows the traffic lights with the menu bar, without
  /// the capsule.
  private func updateWindowControls(animated: Bool) {
    let isFullScreen = window.styleMask.contains(.fullScreen)
    let showsButtons = isToolbarVisible || isFullScreen
    let showsBackground = isToolbarVisible && !isFullScreen
    // Faded out, they'd still take clicks meant for the page; they're hidden
    // once the fade ends.
    let views = windowControlButtons + [windowControlsBackground]
    for view in views where view.alphaValue == 0 {
      view.isHidden = false
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated ? (showsButtons ? 0.15 : 0.3) : 0
      for button in windowControlButtons {
        button.animator().alphaValue = showsButtons ? 1 : 0
      }
      windowControlsBackground.animator().alphaValue = showsBackground ? 1 : 0
    } completionHandler: {
      MainActor.assumeIsolated {
        for view in views {
          view.isHidden = view.alphaValue == 0
        }
      }
    }
  }

  private func configureButton(_ button: NSButton, action: Selector) {
    button.target = self
    button.action = action
    // Enabled state is pushed by setPageState(_:).
    button.isEnabled = false
  }

  // MARK: FiberWindow

  func setContentsView(_ view: NSView?) {
    if view === contentsView {
      return
    }
    // It was for the tab being switched away from. (The browser opens it
    // again on a New Tab page.)
    commandPalette.close()
    // Shown again for when it comes back; setPageState(_:) hides the New Tab
    // page's.
    contentsView?.isHidden = false
    contentsView?.removeFromSuperview()
    contentsView = view
    guard let view, let content = window.contentView else {
      return
    }
    // The page fills the window; the toolbar and tab picker float over it.
    view.frame = content.bounds
    view.autoresizingMask = [.width, .height]
    // Below everything else.
    content.addSubview(view, positioned: .below, relativeTo: nil)
  }

  func setPageState(_ state: FiberPageState) {
    window.title = state.title.isEmpty ? "Fiber" : state.title
    pageURL = state.url
    isNewTabPage = state.isNewTabPage
    newTabView.isHidden = !isNewTabPage
    // Hidden rather than just covered, so it doesn't take focus or clicks.
    contentsView?.isHidden = isNewTabPage
    toolbar.setAddress(state.displayURL)
    toolbar.backButton.isEnabled = state.canGoBack
    toolbar.forwardButton.isEnabled = state.canGoForward
    toolbar.reloadButton.isEnabled = true
    isLoading = state.isLoading
    toolbar.setLoading(isLoading)
  }

  func setTabs(_ tabs: [FiberTabState], activeTabID: Int) {
    tabPicker.setTabs(tabs, activeTabID: activeTabID)
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

  func setControlsVisible(_ visible: Bool) {
    areControlsVisible = visible
    if !visible {
      tabPicker.close()
      closeCommandPalette()
    }
    tabPicker.isHidden = !visible
    updateToolbar(animated: false)
  }

  func showCommandPalette() {
    tabPicker.close()
    commandPalette.open(text: pageURL)
  }

  /// Closes the command palette, returning focus to the page.
  private func closeCommandPalette() {
    guard commandPalette.isOpen else {
      return
    }
    commandPalette.close()
    actions.focusPage()
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

  @objc private func addressClicked(_ sender: Any?) {
    showCommandPalette()
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

  func windowWillEnterFullScreen(_ notification: Notification) {
    updateWindowControls(animated: false)
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    actions.windowDidChangeFullScreen()
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    updateWindowControls(animated: true)
    actions.windowDidChangeFullScreen()
  }
}

/// Sends menu actions that nothing in the responder chain handles to the
/// window's actions, so the main menu acts on this window's browser while
/// it's key. Show Toolbar (-toggleToolbarShown:) shows Fiber's toolbar.
private final class BrowserWindow: NSWindow {
  weak var menuActionTarget: (any FiberWindowActions)?
  weak var controller: BrowserWindowController?

  override func toggleToolbarShown(_ sender: Any?) {
    controller?.toggleToolbar()
  }

  override func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard item.action == #selector(toggleToolbarShown(_:)) else {
      return super.validateMenuItem(item)
    }
    let isVisible = controller?.isToolbarVisible ?? false
    item.title = isVisible ? "Hide Toolbar" : "Show Toolbar"
    return controller != nil
  }

  // NSWindow's private factory for its frame view, which lays out the
  // traffic lights (see WindowFrame).
  @objc(frameViewClassForStyleMask:)
  class func frameViewClass(forStyleMask styleMask: UInt) -> AnyClass {
    let selector = #selector(frameViewClass(forStyleMask:))
    typealias Factory = @convention(c) (AnyClass, Selector, UInt) -> AnyClass
    guard let method = class_getClassMethod(NSWindow.self, selector) else {
      return NSView.self
    }
    let base: AnyClass = unsafeBitCast(
      method_getImplementation(method), to: Factory.self)(
      self, selector, styleMask)
    return WindowFrame.frameViewClass(
      base: base, layout: BrowserWindowController.windowControlsLayout)
  }

  override func supplementalTarget(forAction action: Selector, sender: Any?)
    -> Any?
  {
    if let menuActionTarget, menuActionTarget.responds(to: action) {
      return menuActionTarget
    }
    return super.supplementalTarget(forAction: action, sender: sender)
  }
}
