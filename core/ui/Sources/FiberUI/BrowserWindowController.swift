import AppKit
import FiberBridge

@objc @implementation extension FiberWindowFactory {
  class func window(withFrame frame: NSRect, actions: any FiberWindowActions)
    -> any FiberWindow
  {
    BrowserWindowController(frame: frame, actions: actions)
  }
}

/// A browser window and its native chrome, all floating over the page.
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

  static func controller(for window: NSWindow) -> BrowserWindowController? {
    (window as? BrowserWindow)?.controller
  }

  static var all: [BrowserWindowController] {
    NSApp.windows.compactMap { ($0 as? BrowserWindow)?.controller }
  }
  var omnibox: any FiberOmnibox { commandPalette }
  var extensions: any FiberExtensions { extensionsController }

  private let browserWindow: BrowserWindow
  private let actions: any FiberWindowActions
  private let toolbar = Toolbar()
  private let tabPicker = TabPicker()
  private let tabSidebar = TabSidebar()
  private let commandPalette = CommandPalette()
  private lazy var extensionsController = ExtensionsController(
    bar: toolbar.extensionsBar,
    isBarShown: { [weak self] in self?.isToolbarVisible ?? false },
    hiddenMenuButtonRect: { [weak self] in
      guard let self, let content = self.window.contentView else {
        return nil
      }
      return (content, self.toolbar.extensionsMenuButtonRect(in: content))
    })
  private let newTabView = NewTabView()
  /// The page and the gutter behind it, which the veil blurs as one.
  private let pageArea = NSView()
  /// The page and the New Tab page over it, with its corners rounded like the
  /// window's. It stops short of the window's right edge, where the gutter
  /// shows the tab stack behind it.
  private let pageView = NSView()
  private let gutter = PageGutter()
  /// Whether the active tab is on Fiber's New Tab page, which `newTabView`
  /// draws over the (empty) page.
  private var isNewTabPage = false
  private let progressBar = LoadProgressBar()
  private let statusBubble = StatusBubble()
  /// Blurs the page and darkens the window while it waits on the user.
  private lazy var veil = Veil(blurring: pageArea)
  private lazy var historySwipe = HistorySwipe(pageArea: pageArea, page: pageView)
  /// What the window is waiting on the user for, over the veil.
  private var prompt: VeilPrompt?
  private weak var responderBeforePrompt: NSResponder?
  private let windowControlsBackground = RimmedGlassView(
    rimWidth: BrowserWindowController.windowControlsRimWidth)
  /// Toggled with Command-S; the tab sidebar shows with the toolbar.
  private var isToolbarShown = false
  /// The toolbar, tab sidebar and tab picker hide while a page is fullscreen.
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
    // Pages under the title bar get its clicks and don't move the window
    // (patches/chromium/content-app_shim_remote_cocoa-…); only the capsules
    // do. BrowserWindow moves the traffic lights (see windowControlsLayout).
    window.collectionBehavior.insert(.fullScreenPrimary)
    // Fiber has its own tabs; keep AppKit from merging windows.
    window.tabbingMode = .disallowed

    let content = window.contentView!
    pageArea.frame = content.bounds
    pageArea.autoresizingMask = [.width, .height]
    pageArea.wantsLayer = true
    content.addSubview(pageArea)
    historySwipe.place = { [weak self] view, above in
      guard let self else {
        return
      }
      self.window.contentView?.addSubview(
        view, positioned: above ? .above : .below, relativeTo: self.pageArea)
    }

    // Behind the page, and under its edge.
    let gutterWidth = PageGutter.width + PageGutter.underlap
    gutter.frame = NSRect(
      x: content.bounds.width - gutterWidth, y: 0, width: gutterWidth,
      height: content.bounds.height)
    gutter.autoresizingMask = [.height, .minXMargin]
    pageArea.addSubview(gutter)

    pageView.frame = NSRect(
      x: 0, y: 0, width: content.bounds.width - PageGutter.width,
      height: content.bounds.height)
    pageView.autoresizingMask = [.width, .height]
    pageView.wantsLayer = true
    // Clips the page's own layer too.
    pageView.layer?.masksToBounds = true
    pageView.layer?.cornerRadius = PageGutter.cornerRadius
    pageView.layer?.cornerCurve = .continuous
    pageArea.addSubview(pageView)
    updatePageCorners()

    // Over the page (see setContentsView(_:)).
    newTabView.frame = pageView.bounds
    newTabView.autoresizingMask = [.width, .height]
    newTabView.isHidden = true
    newTabView.onClick = { [weak self] in self?.showCommandPalette() }
    pageView.addSubview(newTabView)

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

    // Below the toolbar, level with its right end.
    tabSidebar.frame = NSRect(
      x: content.bounds.width - Self.edgeInset - TabSidebar.width,
      y: Self.edgeInset, width: TabSidebar.width,
      height: toolbar.frame.minY - Toolbar.spacing - Self.edgeInset)
    tabSidebar.autoresizingMask = [.height, .minXMargin]
    tabSidebar.onSelect = { [weak self] tabID in
      self?.actions.selectTab(withID: tabID)
    }
    content.addSubview(tabSidebar)
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
    commandPalette.onOpen = { [weak self] in self?.tabPicker.close() }
    commandPalette.onDismiss = { [weak self] in self?.closeCommandPalette() }
    content.addSubview(commandPalette)

    // Over everything; what the window waits on goes over it.
    veil.dimView.frame = content.bounds
    veil.dimView.autoresizingMask = [.width, .height]
    content.addSubview(veil.dimView)

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

  fileprivate func toggleToolbar() {
    isToolbarShown = !isToolbarVisible
    if !isToolbarShown {
      extensionsController.closeMenu()
    }
    updateToolbar(animated: true)
  }

  /// The tab sidebar and the traffic lights show with the toolbar. The
  /// sidebar lists the tabs in place of the tab picker's panel.
  private func updateToolbar(animated: Bool) {
    let isVisible = isToolbarVisible
    let views: [NSView] = [toolbar, tabSidebar]
    if isVisible {
      for view in views {
        view.isHidden = false
      }
    }
    tabPicker.isPanelEnabled = !isVisible
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated ? (isVisible ? 0.18 : 0.25) : 0
      for view in views {
        view.animator().alphaValue = isVisible ? 1 : 0
      }
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        // Hidden, so their controls don't take clicks or focus.
        if let self, !self.isToolbarVisible {
          for view in views {
            view.isHidden = true
          }
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

  /// The traffic lights and their capsule show with the toolbar. While the
  /// window is fullscreen, AppKit shows the traffic lights with the menu bar,
  /// without the capsule.
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
    historySwipe.reset()
    contentsView?.removeFromSuperview()
    contentsView = view
    guard let view else {
      return
    }
    // The toolbar and tab picker float over the page.
    view.frame = pageView.bounds
    view.autoresizingMask = [.width, .height]
    pageView.addSubview(view, positioned: .below, relativeTo: newTabView)
  }

  func setPageState(_ state: FiberPageState) {
    window.title = state.title.isEmpty ? "Fiber" : state.title
    isNewTabPage = state.isNewTabPage
    newTabView.isHidden = !isNewTabPage
    // The stack steps from what shows as the page: the New Tab page is drawn
    // in the window's background color, and a page without a background of
    // its own is white.
    gutter.pageColor =
      isNewTabPage
      ? .windowBackgroundColor : state.backgroundColor ?? .white
    toolbar.setAddress(state.displayURL)
    toolbar.backButton.isEnabled = state.canGoBack
    toolbar.forwardButton.isEnabled = state.canGoForward
    toolbar.reloadButton.isEnabled = true
    isLoading = state.isLoading
    toolbar.setLoading(isLoading)
  }

  func setTabs(_ tabs: [FiberTabState], activeTabID: Int) {
    tabPicker.setTabs(tabs, activeTabID: activeTabID)
    tabSidebar.setTabs(tabs, activeTabID: activeTabID)
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
      extensionsController.closeMenu()
    }
    tabPicker.isHidden = !visible
    // A fullscreen page gets the whole window.
    gutter.isHidden = !visible
    pageView.frame = pageArea.bounds.divided(
      atDistance: visible ? PageGutter.width : 0, from: .maxXEdge
    ).remainder
    updatePageCorners()
    updateToolbar(animated: false)
  }

  /// Rounds the page like the window: against the gutter, and at the
  /// window's own corners. A fullscreen page, and the page's edges against a
  /// fullscreen window's screen, stay square.
  private func updatePageCorners(windowFullScreen: Bool? = nil) {
    var corners: CACornerMask = []
    if areControlsVisible {
      corners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
      if !(windowFullScreen ?? window.styleMask.contains(.fullScreen)) {
        corners.formUnion([.layerMinXMinYCorner, .layerMinXMaxYCorner])
      }
    }
    pageView.layer?.maskedCorners = corners
  }

  // MARK: Veil

  private static let promptFadeDuration: TimeInterval = 0.2
  /// How long the veil stays after a prompt goes, for the next one: quitting
  /// asks each page in turn.
  private static let veilLingerDuration: TimeInterval = 0.15

  /// Draws the veil to `amount` (see Veil); it stays fully drawn while a
  /// prompt is up.
  func setVeil(
    _ amount: CGFloat, duration: TimeInterval,
    timing: CAMediaTimingFunctionName = .easeInEaseOut
  ) {
    veil.setAmount(
      prompt == nil ? amount : 1, duration: duration, timing: timing)
  }

  /// Shows `prompt` over the veil, in place of any other (whose onRemoved is
  /// called), and brings the window forward: it may have faded out as the user
  /// quit.
  func present(_ prompt: VeilPrompt) {
    if let replaced = self.prompt {
      replaced.removeFromSuperview()
      replaced.onRemoved?()
    }
    if self.prompt == nil {
      responderBeforePrompt = window.firstResponder
    }
    self.prompt = prompt
    tabPicker.close()
    closeCommandPalette()

    let content = window.contentView!
    prompt.frame = content.bounds
    prompt.autoresizingMask = [.width, .height]
    prompt.alphaValue = 0
    content.addSubview(prompt)
    veil.setAmount(1, duration: 0.25, timing: .easeOut)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.promptFadeDuration
      prompt.animator().alphaValue = 1
      if window.alphaValue < 1 {
        window.animator().alphaValue = 1
      }
    }
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(prompt)
  }

  /// Takes `prompt` down, if it's still up, returning focus to where it was.
  /// The veil lifts unless another prompt follows.
  func dismiss(_ prompt: VeilPrompt) {
    guard prompt === self.prompt else {
      return
    }
    self.prompt = nil
    if window.firstResponder === prompt {
      window.makeFirstResponder(responderBeforePrompt)
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.promptFadeDuration
      prompt.animator().alphaValue = 0
    } completionHandler: {
      MainActor.assumeIsolated { prompt.removeFromSuperview() }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.veilLingerDuration) {
      [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.prompt == nil else {
          return
        }
        self.veil.setAmount(0, duration: 0.25, timing: .easeOut)
      }
    }
  }

  func beginHistorySwipe(
    in direction: FiberHistorySwipeDirection, snapshot: NSImage?
  ) {
    tabPicker.close()
    historySwipe.begin(direction: direction, snapshot: snapshot)
  }

  func updateHistorySwipe(_ progress: Double) {
    historySwipe.update(progress: progress)
  }

  func releaseHistorySwipe(_ completion: @escaping (Bool) -> Void) {
    historySwipe.release(completion)
  }

  func endHistorySwipeNavigating(_ navigating: Bool) {
    historySwipe.end(navigating: navigating)
  }

  func finishHistorySwipeNavigation() {
    historySwipe.finish()
  }

  /// Opens the command palette, where the browser puts the page's URL.
  private func showCommandPalette() {
    commandPalette.focus()
  }

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
    // A prompt is waiting on the user first.
    if prompt == nil {
      actions.windowShouldClose()
    }
    return false
  }

  func windowDidBecomeMain(_ notification: Notification) {
    actions.windowDidBecomeMain()
  }

  func windowWillClose(_ notification: Notification) {
    // What was waiting on the user goes unanswered.
    if let prompt {
      self.prompt = nil
      prompt.onRemoved?()
    }
    extensionsController.windowWillClose()
  }

  func windowDidResignMain(_ notification: Notification) {
    actions.windowDidResignMain()
  }

  func windowWillEnterFullScreen(_ notification: Notification) {
    updateWindowControls(animated: false)
    updatePageCorners(windowFullScreen: true)
  }

  func windowWillExitFullScreen(_ notification: Notification) {
    updatePageCorners(windowFullScreen: false)
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
