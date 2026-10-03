import AppKit
import FiberBridge

@objc @implementation extension FiberWindowFactory {
  class func window(
    withFrame frame: NSRect, actions: any FiberWindowActions,
    tabIndex: any FiberTabIndex, incognito: Bool
  ) -> any FiberWindow {
    BrowserWindowController(
      frame: frame, actions: actions, tabIndex: tabIndex,
      isIncognito: incognito)
  }

  class func startupWindow(withFrame frame: NSRect) -> any FiberWindow {
    let controller = BrowserWindowController(
      frame: frame, actions: nil, tabIndex: nil, isIncognito: false)
    controller.isPageHeld = true
    return controller
  }
}

/// A browser window and its native chrome, all floating over the page.
@MainActor
final class BrowserWindowController: NSObject, FiberWindow {
  private static let defaultWindowSize = NSSize(width: 1280, height: 820)
  private static let minWindowSize = NSSize(width: 480, height: 320)
  /// How far the traffic lights' capsule and the find bar float from the
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
  /// The window's own corner radius, which the page's corners match.
  static let pageCornerRadius: CGFloat = 16
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
  var omnibox: any FiberOmnibox { omnibar }
  var extensions: any FiberExtensions { extensionsController }
  var findBar: any FiberFindBar { madeFindBar ?? makeFindBar() }

  private let browserWindow: BrowserWindow
  var actions: (any FiberWindowActions)? {
    didSet { browserWindow.menuActionTarget = actions }
  }
  var tabIndex: (any FiberTabIndex)?
  private let tabPicker = TabPicker()
  /// Toggled with Command-S. Over everything but the traffic lights' capsule
  /// and the veil, one at a time with the omnibar and the command palette.
  fileprivate let tabOverlay: TabOverlay
  /// Under the tab overlay, the omnibar and the command palette.
  private let panelDimming = PanelDimming()
  private var isPanelDimmingUpdateScheduled = false
  /// The active tab's page's mean CIE L*, as last measured, for the dimming
  /// over it.
  private var pageLightness: Double?
  /// Nil until first used (see makeOmnibar()).
  private var madeOmnibar: Omnibar?
  private var omnibar: Omnibar { madeOmnibar ?? makeOmnibar() }
  /// Made the first time it opens (see makeCommandPalette()).
  private var commandPalette: CommandPalette?
  /// Made the first time the browser finds in the window (see makeFindBar()).
  private var madeFindBar: FindBar?
  /// The window's tabs, for a command palette made later.
  private var windowTabs: [FiberTabState] = []
  private var activeTabID = 0
  private var pins: [FiberPinState] = []
  /// Whether the window has pins at all, which Incognito's don't.
  private var canPin = false
  private lazy var extensionsController = ExtensionsController(
    bar: tabOverlay.extensionsBar, bubbles: extensionBubbles,
    isBarShown: { [weak self] in self?.tabOverlay.isOpen ?? false },
    hiddenMenuButtonRect: { [weak self] in
      guard let self, let content = self.window.contentView else {
        return nil
      }
      // In the window's top-right corner, where the find bar's close button
      // goes.
      let size = GlassCapsule.buttonSize
      let inset = Self.edgeInset + (GlassCapsule.height - size) / 2
      return (
        content,
        NSRect(
          x: content.bounds.maxX - inset - size,
          y: content.bounds.maxY - inset - size, width: size, height: size)
      )
    })
  private let newTabView: NewTabView
  private let sadTabView = SadTabView()
  /// Over the page, under the tab picker.
  private let extensionBubbles = ExtensionBubbles()
  /// Whose browser the user is in: the window's, or an extension window's,
  /// while its page has focus.
  private var activeBrowser = ActiveBrowser.none
  /// The page, and the active tab's DevTools filling the content area under
  /// it; the veil blurs them.
  private let contentArea = NSView()
  /// Holds DevTools' view, rounded like the window.
  private let devToolsArea = NSView()
  private var devTools: FiberDevTools?
  /// Holds `pageView`, where DevTools puts the page; swiping between pages
  /// moves it.
  private let pageArea = NSView()
  /// The page and what the window draws over it (the New Tab page, a sad tab),
  /// with its corners rounded like the window's.
  private let pageView = NSView()
  /// Whether the active tab is on Fiber's New Tab page, which `newTabView`
  /// draws over the (empty) page.
  private var isNewTabPage = false
  /// A startup window's page, and the omnibar over it, don't show until
  /// showPage(). The New Tab page's mark, which is usually what the page turns
  /// out to be, stands in meanwhile.
  fileprivate var isPageHeld = false {
    didSet {
      pageArea.alphaValue = isPageHeld ? 0 : 1
      madeOmnibar?.view.isHeld = isPageHeld
      updateHeldPagePlaceholder()
    }
  }
  /// Under the page while it's held.
  private var heldPagePlaceholder: NewTabView?
  /// Over the page, wherever DevTools puts it, even an emulated device's
  /// screen.
  private let pageOverlay = PassthroughView()
  private let progressBar = LoadProgressBar()
  private let statusBubble = StatusBubble()
  /// The window's floating controls, over all of the content area that isn't
  /// DevTools, laid out as if it were the window.
  private let controlsView = PassthroughView()
  /// Blurs the page and darkens the window while it waits on the user.
  private lazy var veil = Veil(blurring: contentArea)
  private lazy var historySwipe = HistorySwipe(pageArea: pageArea, page: pageView)
  /// What the window is waiting on the user for, over the veil.
  private var prompt: (any VeilContent)?
  private weak var responderBeforePrompt: NSResponder?
  private let windowControlsBackground = RimmedGlassView(
    rimWidth: BrowserWindowController.windowControlsRimWidth)
  /// Set while a page is fullscreen (a video, say), which shows alone.
  private var isPageFullScreen = false
  /// The tab overlay and tab picker hide while a page is fullscreen, and
  /// while DevTools emulates a device, whose controls take their place.
  private var areControlsVisible: Bool {
    !isPageFullScreen && devTools?.emulatesDevice != true
  }
  private weak var contentsView: NSView?

  init(
    frame: NSRect, actions: (any FiberWindowActions)?,
    tabIndex: (any FiberTabIndex)?, isIncognito: Bool
  ) {
    self.actions = actions
    self.tabIndex = tabIndex
    tabOverlay = TabOverlay(isIncognito: isIncognito)
    newTabView = NewTabView(isIncognito: isIncognito)
    let styleMask: NSWindow.StyleMask = [
      .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
    ]
    // At its final size, so that it's laid out once.
    browserWindow = BrowserWindow(
      contentRect: frame.isEmpty
        ? NSRect(origin: .zero, size: Self.defaultWindowSize)
        : NSWindow.contentRect(forFrameRect: frame, styleMask: styleMask),
      styleMask: styleMask,
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
    // Like Safari's Private Browsing windows. The page keeps the system's
    // appearance.
    if isIncognito {
      window.appearance = NSAppearance(named: .darkAqua)
    }
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
    contentArea.frame = content.bounds
    contentArea.autoresizingMask = [.width, .height]
    contentArea.wantsLayer = true
    content.addSubview(contentArea)

    devToolsArea.frame = contentArea.bounds
    devToolsArea.autoresizingMask = [.width, .height]
    devToolsArea.wantsLayer = true
    devToolsArea.layer?.masksToBounds = true
    devToolsArea.layer?.cornerRadius = Self.pageCornerRadius
    devToolsArea.layer?.cornerCurve = .continuous
    devToolsArea.isHidden = true
    contentArea.addSubview(devToolsArea)

    pageArea.frame = contentArea.bounds
    pageArea.autoresizingMask = [.width, .height]
    pageArea.wantsLayer = true
    // A swipe moves the page within it, clear of DevTools.
    pageArea.layer?.masksToBounds = true
    contentArea.addSubview(pageArea)
    historySwipe.place = { [weak self] view, above in
      guard let self else {
        return
      }
      self.contentArea.addSubview(
        view, positioned: above ? .above : .below, relativeTo: self.pageArea)
    }

    pageView.frame = pageArea.bounds
    pageView.autoresizingMask = [.width, .height]
    pageView.wantsLayer = true
    // Clips the page's own layer too.
    pageView.layer?.masksToBounds = true
    pageView.layer?.cornerRadius = Self.pageCornerRadius
    pageView.layer?.cornerCurve = .continuous
    pageArea.addSubview(pageView)
    updatePageCorners()

    // Over the page (see setContentsView(_:)).
    newTabView.frame = pageView.bounds
    newTabView.autoresizingMask = [.width, .height]
    newTabView.isHidden = true
    newTabView.onClick = { [weak self] in self?.showOmnibar() }
    pageView.addSubview(newTabView)
    sadTabView.frame = pageView.bounds
    sadTabView.autoresizingMask = [.width, .height]
    sadTabView.isHidden = true
    sadTabView.onButton = { [weak self] in self?.actions?.pressSadTabButton() }
    sadTabView.onHelp = { [weak self] in self?.actions?.openSadTabHelp() }
    pageView.addSubview(sadTabView)

    pageOverlay.frame = content.bounds
    pageOverlay.autoresizingMask = [.width, .height]
    content.addSubview(pageOverlay)
    progressBar.frame = NSRect(
      x: 0, y: content.bounds.height - Self.progressBarHeight,
      width: content.bounds.width, height: Self.progressBarHeight)
    progressBar.autoresizingMask = [.width, .minYMargin]
    pageOverlay.addSubview(progressBar)

    statusBubble.setFrameOrigin(
      NSPoint(x: Self.statusBubbleInset, y: Self.statusBubbleInset))
    statusBubble.autoresizingMask = [.maxXMargin, .maxYMargin]
    pageOverlay.addSubview(statusBubble)

    controlsView.frame = content.bounds
    controlsView.autoresizingMask = [.width, .height]
    controlsView.wantsLayer = true
    // The tab picker's bump straddles the edge, and stays off DevTools.
    controlsView.layer?.masksToBounds = true
    content.addSubview(controlsView)

    extensionBubbles.frame = content.bounds
    extensionBubbles.autoresizingMask = [.width, .height]
    extensionBubbles.onFocusPage = { [weak self] in self?.actions?.focusPage() }
    extensionBubbles.onRemove = { [weak self] in self?.updateActiveBrowser() }
    controlsView.addSubview(extensionBubbles)

    tabPicker.frame = NSRect(
      x: content.bounds.width - TabPicker.width, y: 0, width: TabPicker.width,
      height: content.bounds.height)
    tabPicker.autoresizingMask = [.height, .minXMargin]
    tabPicker.onSelect = { [weak self] tabID in
      self?.actions?.selectTab(withID: tabID)
    }
    tabPicker.onClose = { [weak self] tabID in
      self?.actions?.closeTab(withID: tabID)
    }
    tabPicker.onMenu = { [weak self] tabID, event in
      self?.showMenu(forTabWithID: tabID, event: event, in: self?.tabPicker)
    }
    controlsView.addSubview(tabPicker)

    configureTabOverlay()
    configureWindowControls()
    updateWindowControls(animated: false)

    // Over everything; what the window waits on goes over it.
    veil.dimView.frame = content.bounds
    veil.dimView.autoresizingMask = [.width, .height]
    content.addSubview(veil.dimView)

    if frame.isEmpty {
      window.center()
    } else if window.frame != frame {
      window.setFrame(frame, display: false)
    }
  }

  /// Over everything but the veil, one at a time with the command palette
  /// (see makeCommandPalette()). Made on first use, which for a startup window
  /// is once the browser takes it, so the window shows sooner.
  private func makeOmnibar() -> Omnibar {
    let omnibar = Omnibar()
    let content = window.contentView!
    omnibar.view.frame = content.bounds
    omnibar.view.autoresizingMask = [.width, .height]
    omnibar.view.isHeld = isPageHeld
    content.addSubview(
      omnibar.view, positioned: .below, relativeTo: veil.dimView)
    omnibar.onOpen = { [weak self] in
      self?.tabPicker.close()
      self?.commandPalette?.close()
      self?.closeTabOverlay(restoringFocus: false)
    }
    omnibar.onDismiss = { [weak self] in self?.closeOmnibar() }
    omnibar.canOpenForTab = { [weak self] in self?.tabOverlay.isOpen != true }
    omnibar.view.onShowOrHide = { [weak self] in
      self?.schedulePanelDimmingUpdate()
    }
    madeOmnibar = omnibar
    return omnibar
  }

  /// Over the page, under extension windows' bubbles, which move out of its
  /// way.
  private func makeFindBar() -> FindBar {
    let findBar = FindBar()
    extensionBubbles.superview?.addSubview(
      findBar, positioned: .below, relativeTo: extensionBubbles)
    findBar.autoresizingMask = [.minXMargin, .minYMargin]
    findBar.onOpen = { [weak self] in
      self?.tabPicker.close()
      self?.madeOmnibar?.close()
      self?.commandPalette?.close()
      self?.closeTabOverlay(restoringFocus: false)
    }
    findBar.onShowOrHide = { [weak self] in
      self?.placeFindBar(animated: true)
    }
    madeFindBar = findBar
    placeFindBar(animated: false)
    return findBar
  }

  /// In the top-right corner.
  private func placeFindBar(animated: Bool) {
    guard let findBar = madeFindBar, let container = findBar.superview else {
      return
    }
    let bounds = container.bounds
    let top = bounds.maxY - Self.edgeInset
    let width = min(FindBar.width, bounds.width - 2 * Self.edgeInset)
    let frame = NSRect(
      x: bounds.maxX - Self.edgeInset - width, y: top - FindBar.height,
      width: width, height: FindBar.height)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated ? 0.3 : 0
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      findBar.animator().frame = frame
    }
    extensionBubbles.setKeepClear(
      findBar.isOpen
        ? extensionBubbles.convert(frame, from: container) : .null,
      animated: animated)
  }

  private func updateHeldPagePlaceholder() {
    guard isPageHeld else {
      heldPagePlaceholder?.removeFromSuperview()
      heldPagePlaceholder = nil
      return
    }
    guard heldPagePlaceholder == nil else {
      return
    }
    // Only startup windows hold their page, and they're never Incognito.
    let placeholder = NewTabView(isIncognito: false)
    placeholder.frame = pageArea.frame
    placeholder.autoresizingMask = [.width, .height]
    contentArea.addSubview(placeholder, positioned: .below, relativeTo: pageArea)
    heldPagePlaceholder = placeholder
  }

  private func configureTabOverlay() {
    let content = window.contentView!
    tabOverlay.frame = content.bounds
    tabOverlay.autoresizingMask = [.width, .height]
    tabOverlay.onSelect = { [weak self] tabID in
      self?.actions?.selectTab(withID: tabID)
    }
    tabOverlay.onClose = { [weak self] tabID in
      self?.actions?.closeTab(withID: tabID)
    }
    tabOverlay.onOpenPin = { [weak self] pinID in
      self?.actions?.openPin(withID: pinID)
    }
    tabOverlay.onMovePin = { [weak self] pinID, index in
      self?.actions?.movePin(withID: pinID, to: index)
    }
    tabOverlay.onUnpin = { [weak self] pinID in
      self?.actions?.unpinPin(withID: pinID)
    }
    tabOverlay.onPinMenu = { [weak self] pin, event in
      self?.showMenu(for: pin, event: event)
    }
    tabOverlay.onTabMenu = { [weak self] tabID, event in
      self?.showMenu(forTabWithID: tabID, event: event, in: self?.tabOverlay)
    }
    tabOverlay.onAddressClick = { [weak self] in self?.showOmnibar() }
    tabOverlay.onDismiss = { [weak self] in self?.closeTabOverlay() }
    tabOverlay.onShowOrHide = { [weak self] in
      self?.schedulePanelDimmingUpdate()
    }
    panelDimming.frame = content.bounds
    panelDimming.autoresizingMask = [.width, .height]
    content.addSubview(panelDimming)
    content.addSubview(tabOverlay)
  }

  /// Once what's opening in place of what closed has opened, so switching
  /// between them keeps the dimming.
  private func schedulePanelDimmingUpdate() {
    guard !isPanelDimmingUpdateScheduled else {
      return
    }
    isPanelDimmingUpdateScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else {
          return
        }
        self.isPanelDimmingUpdateScheduled = false
        let shown =
          self.tabOverlay.isOpen || self.madeOmnibar?.view.isShown == true
          || self.commandPalette?.view.isShown == true
        if shown && !self.panelDimming.isShown {
          self.measurePageLightness()
        }
        self.panelDimming.setShown(shown)
      }
    }
  }

  /// Darkens the panels' dimming and the veil for how light the page looks:
  /// at once as it last did, or as the window's background, which shows until
  /// the page draws (and the New Tab page matches), then as it does now.
  private func measurePageLightness() {
    applyPageLightness(pageLightness ?? windowBackgroundLightness)
    let contentsView = contentsView
    actions?.capturePageThumbnail { [weak self] thumbnail in
      MainActor.assumeIsolated {
        guard let self, self.contentsView === contentsView, let thumbnail,
          let lightness = Dimming.lightness(of: thumbnail)
        else {
          return
        }
        self.pageLightness = lightness
        self.applyPageLightness(lightness)
      }
    }
  }

  private func applyPageLightness(_ lightness: Double) {
    panelDimming.setPageLightness(lightness)
    veil.setPageLightness(lightness)
  }

  private var windowBackgroundLightness: Double {
    var lightness: Double?
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
      lightness = Dimming.lightness(of: window.backgroundColor)
    }
    return lightness ?? 100
  }

  /// Not while a prompt waits on the user, or the controls are hidden.
  fileprivate var canShowTabOverlay: Bool {
    actions != nil && prompt == nil && areControlsVisible
  }

  fileprivate func toggleTabOverlay() {
    if tabOverlay.isOpen {
      closeTabOverlay()
    } else if canShowTabOverlay {
      tabPicker.close()
      madeOmnibar?.close()
      commandPalette?.close()
      tabOverlay.open()
      updateWindowControls(animated: true)
    }
  }

  /// Gives the active tab the keyboard back, unless what's opening in the
  /// overlay's place takes it. A New Tab page that became active under the
  /// overlay opens the omnibar only now.
  private func closeTabOverlay(restoringFocus: Bool = true) {
    guard tabOverlay.isOpen else {
      return
    }
    tabOverlay.close()
    extensionsController.closeMenu()
    updateWindowControls(animated: true)
    if restoringFocus {
      actions?.restoreFocus()
    }
  }

  private var windowControlButtons: [NSButton] {
    [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
      .compactMap { window.standardWindowButton($0) }
  }

  /// Puts a glass capsule behind the traffic lights, which stay in the title
  /// bar above it, over the tab overlay's dimming. Dragging the capsule moves
  /// the window.
  private func configureWindowControls() {
    // Where AppKit put the traffic lights, in the content view's coordinates.
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
    window.contentView!.addSubview(windowControlsBackground)
  }

  /// The traffic lights and their capsule show with the tab overlay. While
  /// the window is fullscreen, AppKit shows the traffic lights with the menu
  /// bar, without the capsule.
  private func updateWindowControls(animated: Bool) {
    let isFullScreen = window.styleMask.contains(.fullScreen)
    let showsButtons = tabOverlay.isOpen || isFullScreen
    let showsBackground = tabOverlay.isOpen && !isFullScreen
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

  // MARK: FiberWindow

  func setContentsView(_ view: NSView?) {
    if view === contentsView {
      return
    }
    // They were for the tab being switched away from. (The browser opens the
    // omnibar again on a New Tab page.)
    madeOmnibar?.close()
    commandPalette?.close()
    historySwipe.reset()
    contentsView?.removeFromSuperview()
    contentsView = view
    pageLightness = nil
    guard let view else {
      return
    }
    // The window's controls float over the page.
    view.frame = pageView.bounds
    view.autoresizingMask = [.width, .height]
    // Chrome hides a page made in the background (a ⌘-clicked link, a restored
    // tab) until its host shows it; hidden, it never draws.
    view.isHidden = false
    pageView.addSubview(view, positioned: .below, relativeTo: newTabView)
    if panelDimming.isShown || veil.amount > 0 {
      measurePageLightness()
    }
  }

  func setDevTools(_ devTools: FiberDevTools?) {
    let previous = self.devTools
    self.devTools = devTools
    if devTools?.view !== previous?.view {
      let hadFocus =
        previous.map { isFirstResponder(in: $0.view) } ?? false
      previous?.view.removeFromSuperview()
      if let view = devTools?.view {
        view.frame = devToolsArea.bounds
        view.autoresizingMask = [.width, .height]
        devToolsArea.addSubview(view)
      }
      // AppKit leaves the window itself focused.
      if hadFocus {
        actions?.focusPage()
      }
    }
    devToolsArea.isHidden = devTools == nil
    layoutPage()
    updateMinSize()
    if devTools?.emulatesDevice != previous?.emulatesDevice {
      updateControls()
    }
  }

  func setPageState(_ state: FiberPageState) {
    window.title = state.title.isEmpty ? "Fiber" : state.title
    isNewTabPage = state.isNewTabPage
    newTabView.isHidden = !isNewTabPage || state.sadTab != nil
    if let sadTab = state.sadTab {
      sadTabView.show(sadTab)
    }
    sadTabView.isHidden = state.sadTab == nil
    tabOverlay.setAddress(state.displayURL)
  }

  func showPage() {
    isPageHeld = false
  }

  func setTabs(_ tabs: [FiberTabState], activeTabID: Int) {
    tabPicker.setTabs(tabs, activeTabID: activeTabID)
    tabOverlay.setTabs(tabs, activeTabID: activeTabID)
    // A tab opened in front (Command-T, a link from another app) is where the
    // user's going; tabs already open can become active under the overlay.
    if !windowTabs.isEmpty,
      !windowTabs.contains(where: { $0.tabID == activeTabID })
    {
      closeTabOverlay()
    }
    windowTabs = tabs
    self.activeTabID = activeTabID
    commandPalette?.setWindowTabs(tabs, activeTabID: activeTabID)
  }

  func setPins(_ pins: [FiberPinState]) {
    self.pins = pins
    canPin = true
    tabOverlay.setPins(pins)
  }

  private func showMenu(for pin: FiberPinState, event: NSEvent) {
    guard let actions else {
      return
    }
    NSMenu.popUpContextMenu(
      TabMenus.menu(for: pin, actions: actions), with: event, for: tabOverlay)
  }

  /// A pin's tab, in the tab picker, has its pin's menu.
  private func showMenu(
    forTabWithID tabID: Int, event: NSEvent, in view: NSView?
  ) {
    guard let actions, let view else {
      return
    }
    let menu =
      pins.first { $0.tabID == tabID }.map {
        TabMenus.menu(for: $0, actions: actions)
      }
      ?? TabMenus.menu(forTabWithID: tabID, canPin: canPin, actions: actions)
    NSMenu.popUpContextMenu(menu, with: event, for: view)
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
    isPageFullScreen = !visible
    if isPageFullScreen {
      closeOmnibar()
      closeCommandPalette()
    }
    updateControls()
  }

  private func updateControls() {
    let isVisible = areControlsVisible
    if !isVisible {
      tabPicker.close()
      closeTabOverlay(restoringFocus: false)
    }
    tabPicker.isHidden = !isVisible
    extensionBubbles.isHidden = !isVisible
    updatePageCorners()
  }

  /// Rounds the page and DevTools like the window. A fullscreen page, an
  /// emulated device's screen and a fullscreen window's stay square.
  private func updatePageCorners(windowFullScreen: Bool? = nil) {
    let isWindowFullScreen =
      windowFullScreen ?? window.styleMask.contains(.fullScreen)
    let corners: CACornerMask = [
      .layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner,
      .layerMaxXMaxYCorner,
    ]
    pageView.layer?.maskedCorners =
      !areControlsVisible || isWindowFullScreen ? [] : corners
    devToolsArea.layer?.maskedCorners = isWindowFullScreen ? [] : corners
  }

  // MARK: DevTools

  /// DevTools' own smallest size beside the page (InspectorView.ts), and its
  /// splitter.
  private static let minDevToolsSize = NSSize(width: 251, height: 73)

  /// Puts the page where DevTools says, and the controls over it, unless it's
  /// an emulated device's screen.
  private func layoutPage() {
    let bounds = contentArea.bounds
    var frame = bounds
    if let pageFrame = devTools?.pageFrame, !pageFrame.isEmpty {
      frame = NSRect(
        x: pageFrame.minX, y: bounds.maxY - pageFrame.maxY,
        width: pageFrame.width, height: pageFrame.height)
    }
    let emulatesDevice = devTools?.emulatesDevice == true
    // As the window resizes, until DevTools says otherwise, it keeps its size,
    // and an emulated screen keeps its own.
    let resizing: NSView.AutoresizingMask =
      emulatesDevice ? [.maxXMargin, .minYMargin] : [.width, .height]
    for view in [pageArea, pageOverlay] {
      view.frame = frame
      view.autoresizingMask = resizing
    }
    if !emulatesDevice {
      controlsView.frame = frame
    }
  }

  /// Makes room for docked DevTools beside a page as big as the smallest
  /// window, which DevTools keeps it (DeviceModeView.ts), growing the window
  /// if it's smaller.
  private func updateMinSize() {
    var size = Self.minWindowSize
    switch devTools?.dock {
    case .bottom?:
      size.height += Self.minDevToolsSize.height
    case .right?:
      size.width += Self.minDevToolsSize.width
    default:
      break
    }
    guard size != window.minSize else {
      return
    }
    window.minSize = size
    var frame = window.frame
    guard !window.styleMask.contains(.fullScreen),
      frame.width < size.width || frame.height < size.height
    else {
      return
    }
    // Keeping its top-left corner where it is.
    let height = max(frame.height, size.height)
    frame.origin.y = frame.maxY - height
    frame.size = NSSize(width: max(frame.width, size.width), height: height)
    window.setFrame(frame, display: true)
  }

  private func isFirstResponder(in view: NSView) -> Bool {
    (window.firstResponder as? NSView)?.isDescendant(of: view) ?? false
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
    let amount = prompt == nil ? amount : 1
    if amount > 0, veil.amount == 0 {
      measurePageLightness()
    }
    veil.setAmount(amount, duration: duration, timing: timing)
  }

  /// Shows `prompt` over the veil, in place of any other (whose onRemoved is
  /// called), and brings the window forward: it may have faded out as the user
  /// quit.
  func present(_ prompt: any VeilContent) {
    if let replaced = self.prompt {
      replaced.removeFromSuperview()
      replaced.onRemoved?()
    }
    if self.prompt == nil {
      responderBeforePrompt = window.firstResponder
    }
    self.prompt = prompt
    tabPicker.close()
    closeOmnibar()
    closeCommandPalette()
    closeTabOverlay(restoringFocus: false)

    let content = window.contentView!
    prompt.frame = content.bounds
    prompt.autoresizingMask = [.width, .height]
    prompt.alphaValue = 0
    content.addSubview(prompt)
    setVeil(1, duration: 0.25, timing: .easeOut)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.promptFadeDuration
      prompt.animator().alphaValue = 1
      if window.alphaValue < 1 {
        window.animator().alphaValue = 1
      }
    }
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(prompt.initialFirstResponder ?? prompt)
  }

  /// Takes `prompt` down, if it's still up, returning focus to where it was.
  /// The veil lifts unless another prompt follows.
  func dismiss(_ prompt: any VeilContent) {
    guard prompt === self.prompt else {
      return
    }
    self.prompt = nil
    if let responder = window.firstResponder as? NSView,
      responder.isDescendant(of: prompt)
    {
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

  /// Opens the omnibar, where the browser puts the page's URL.
  private func showOmnibar() {
    omnibar.focus(userInitiated: true)
  }

  private func closeOmnibar() {
    guard madeOmnibar?.isOpen == true else {
      return
    }
    omnibar.close()
    actions?.focusPage()
  }

  /// Not while a prompt waits on the user, or a page is fullscreen.
  fileprivate var canShowCommandPalette: Bool {
    prompt == nil && !isPageFullScreen
  }

  /// Not while a prompt waits on the user, which the switcher would replace.
  var canShowProfileSwitcher: Bool {
    prompt == nil
  }

  func showCommandPalette() {
    if canShowCommandPalette {
      makeCommandPalette()?.open()
    }
  }

  /// Most windows never open it. Nil until the window has its actions.
  private func makeCommandPalette() -> CommandPalette? {
    if let commandPalette {
      return commandPalette
    }
    guard let actions, let content = window.contentView else {
      return nil
    }
    let palette = CommandPalette(
      index: tabIndex as? TabIndex ?? TabIndex(), actions: actions)
    palette.setWindowTabs(windowTabs, activeTabID: activeTabID)
    palette.view.frame = content.bounds
    palette.view.autoresizingMask = [.width, .height]
    content.addSubview(palette.view, positioned: .above, relativeTo: omnibar.view)
    palette.onOpen = { [weak self] in
      self?.tabPicker.close()
      self?.madeOmnibar?.close()
      self?.closeTabOverlay(restoringFocus: false)
    }
    palette.onDismiss = { [weak self] in self?.closeCommandPalette() }
    palette.view.onShowOrHide = { [weak self] in
      self?.schedulePanelDimmingUpdate()
    }
    commandPalette = palette
    return palette
  }

  fileprivate func toggleCommandPalette() {
    if commandPalette?.isOpen == true {
      closeCommandPalette()
    } else {
      showCommandPalette()
    }
  }

  private func closeCommandPalette() {
    guard let commandPalette, commandPalette.isOpen else {
      return
    }
    commandPalette.close()
    actions?.focusPage()
  }

  /// The browser focuses the page when something else navigates it (the
  /// About item in the app menu, say), and the omnibar and command palette
  /// give way, as Chrome's omnibox does.
  fileprivate func firstResponderDidChange() {
    madeFindBar?.firstResponderDidChange()
    let pages = [contentsView, devTools?.view].compactMap { $0 }
    guard pages.contains(where: isFirstResponder(in:)) else {
      return
    }
    madeOmnibar?.close()
    commandPalette?.close()
  }

  // MARK: Active browser

  private enum ActiveBrowser {
    case none
    case window
    case extensionWindow(ExtensionWindowBubble)

    func isSame(as other: ActiveBrowser) -> Bool {
      switch (self, other) {
      case (.none, .none), (.window, .window):
        true
      case (.extensionWindow(let a), .extensionWindow(let b)):
        a === b
      default:
        false
      }
    }
  }

  /// Tells the browsers which of them the user is in, as focus moves between
  /// the page and extension windows' pages, and the window becomes or stops
  /// being main.
  fileprivate func updateActiveBrowser() {
    let next: ActiveBrowser =
      if !window.isMainWindow {
        .none
      } else if let bubble = extensionBubbles.bubble(
        containing: window.firstResponder)
      {
        .extensionWindow(bubble)
      } else {
        .window
      }
    guard !next.isSame(as: activeBrowser) else {
      return
    }
    let previous = activeBrowser
    activeBrowser = next
    switch previous {
    case .none: break
    case .window: actions?.windowDidResignMain()
    case .extensionWindow(let bubble): bubble.didResignActive()
    }
    switch next {
    case .none: break
    case .window: actions?.windowDidBecomeMain()
    case .extensionWindow(let bubble): bubble.didBecomeActive()
    }
  }
}

extension BrowserWindowController: NSWindowDelegate {
  // Closing goes through the browser, which runs unload handlers and closes
  // the tabs first; the window really closes when its owner is done with it.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // A startup window no browser took over has nothing to close first.
    guard let actions else {
      return true
    }
    // A prompt is waiting on the user first.
    if prompt == nil {
      actions.windowShouldClose()
    }
    return false
  }

  func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?)
    -> Any?
  {
    guard let madeOmnibar, client as? NSTextField === madeOmnibar.view.field
    else {
      return nil
    }
    return madeOmnibar.fieldEditor
  }

  func windowDidBecomeMain(_ notification: Notification) {
    updateActiveBrowser()
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
    updateActiveBrowser()
  }

  func windowWillEnterFullScreen(_ notification: Notification) {
    updateWindowControls(animated: false)
    updatePageCorners(windowFullScreen: true)
  }

  func windowWillExitFullScreen(_ notification: Notification) {
    updatePageCorners(windowFullScreen: false)
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    actions?.windowDidChangeFullScreen()
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    updateWindowControls(animated: true)
    actions?.windowDidChangeFullScreen()
  }
}

/// Sends menu actions that nothing in the responder chain handles to the
/// window's actions, so the main menu acts on this window's browser while
/// it's key. Show Tabs (-toggleToolbarShown:) toggles the tab overlay.
private final class BrowserWindow: NSWindow, FiberWindowMenuActions {
  weak var menuActionTarget: (any FiberWindowActions)?
  weak var controller: BrowserWindowController?

  override func toggleToolbarShown(_ sender: Any?) {
    controller?.toggleTabOverlay()
  }

  // Focus moving into or out of an extension window's page changes which
  // browser is active.
  override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    let changed = super.makeFirstResponder(responder)
    controller?.updateActiveBrowser()
    controller?.firstResponderDidChange()
    return changed
  }

  func toggleCommandPalette(_ sender: Any?) {
    controller?.toggleCommandPalette()
  }

  override func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(toggleToolbarShown(_:)):
      let isOpen = controller?.tabOverlay.isOpen ?? false
      item.title = isOpen ? "Hide Tabs" : "Show Tabs"
      return isOpen || controller?.canShowTabOverlay == true
    case #selector(toggleCommandPalette(_:)):
      return controller?.canShowCommandPalette ?? false
    default:
      return super.validateMenuItem(item)
    }
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

/// Holds views over the page without taking the clicks they don't.
private final class PassthroughView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    let view = super.hitTest(point)
    return view === self ? nil : view
  }
}
