import AppKit
import FiberBridge
import SwiftUI

/// The window's tabs, over the dimmed page with Command-S: those that aren't
/// pins', in the tab strip's order, in a panel as wide as the command
/// palette's, with the pins (PinGrid) in rows above it, the page's address
/// and the extensions beside it, the split's spot (SplitSpot) on its other
/// side, and under it the shelves (ShelfBar), whose lists it shows in place
/// of the tabs, and the downloads (DownloadsBubble). Rows drag to a new place
/// in the list, onto a shelf, or onto the split's spot. The arrow keys,
/// Return and Command-W move through, switch to and close them, and holding
/// Option numbers the tabs, for Option and a number to switch to one. This
/// view takes the events and keeps the model; TabOverlayView draws.
@MainActor
final class TabOverlay: NSView, NSViewToolTipOwner {
  /// Called with a tab to switch to, never the active one unless it's to go
  /// on the left of the split. Its owner closes the overlay.
  var onSelect: (Int) -> Void = { _ in }
  /// Called with the ID of a tab to close.
  var onClose: (Int) -> Void = { _ in }
  /// Called with a pin to open, never the active tab's. Its owner closes the
  /// overlay.
  var onOpenPin: (String) -> Void = { _ in }
  /// Called with a pin whose tab should go back to its pinned page, where it
  /// is: the overlay stays.
  var onResetPin: (String) -> Void = { _ in }
  /// Called with a pin dropped in a new place, and its index there, or a
  /// shelf's page and its index among the shelf's.
  var onMovePin: (String, Int) -> Void = { _, _ in }
  /// Called with a tab dropped in a new place in Home's list, and the tab it
  /// goes before, or 0 for after the others.
  var onMoveTab: (Int, Int) -> Void = { _, _ in }
  /// Called with a tab dropped on the split's spot, and the tab it goes on the
  /// right of.
  var onSplit: (Int, Int) -> Void = { _, _ in }
  /// The same for a pin or a shelf's page, which a copy of goes there.
  var onSplitCopy: (String, Int) -> Void = { _, _ in }
  /// Right-clicks on the split's spot, while it has a tab.
  var onSplitMenu: (NSEvent) -> Void = { _ in }
  var onUnpin: (String) -> Void = { _ in }
  /// Right-clicks (or Control-clicks) on a pin or a tab, for their menus.
  var onPinMenu: (FiberPinState, NSEvent) -> Void = { _, _ in }
  var onTabMenu: (Int, NSEvent) -> Void = { _, _ in }
  var onAddressClick: () -> Void = {}
  /// Called with a shelf's page whose tab isn't open here. Its owner closes
  /// the overlay.
  var onOpenShelfPage: (String) -> Void = { _ in }
  var onRemoveShelfPage: (String) -> Void = { _ in }
  /// Called with a tab dropped on a shelf's segment, and the shelf.
  var onMoveTabToShelf: (Int, String) -> Void = { _, _ in }
  /// Called with a shelf's page dropped on another segment, and its shelf, or
  /// "" for Home.
  var onMoveShelfPage: (String, String) -> Void = { _, _ in }
  /// Returns the ID of the shelf it added.
  var onAddShelf: () -> String? = { nil }
  var onRenameShelf: (String, String) -> Void = { _, _ in }
  /// Called once a shelf the user deleted can no longer be undone.
  var onRemoveShelf: (String) -> Void = { _ in }
  /// Right-clicks on a shelf's segment, or on a shelf's page.
  var onShelfMenu: (FiberShelfState, NSEvent) -> Void = { _, _ in }
  var onShelfPageMenu: (FiberPinState, FiberShelfState, NSEvent) -> Void = {
    _, _, _ in
  }
  var onDownloadAction: (DownloadAction) -> Void = { _ in }
  /// Called as the overlay opens over downloads.
  var onDownloadsShown: () -> Void = {}
  /// Called when the overlay is done without switching tabs: the user picked
  /// the active tab, pressed Escape, or clicked outside it. Its owner closes
  /// it.
  var onDismiss: () -> Void = {}
  var onShowOrHide: () -> Void = {}
  let extensionsBar = ExtensionsBar()
  private(set) var isOpen = false

  /// Between the panel and the address and extensions beside it.
  private static let bubbleSpacing: CGFloat = 12
  /// How close the address and extensions come to the window's edge before
  /// they move above the panel and its pins.
  private static let bubbleMargin: CGFloat = 16
  private static let maxAddressWidth: CGFloat = 260
  /// How much of the window's height the panel and what's above it leave
  /// free goes above them, a little less than below.
  private static let topShare: CGFloat = 0.45
  /// How far a pressed pin moves before it's dragged rather than clicked.
  private static let dragThreshold: CGFloat = 4
  /// How far in from the panel's sides a row dragged within the list pulls
  /// out of it, and how far in it drops back in, so it doesn't flicker
  /// between the two at the edge.
  private static let pullOutInset: CGFloat = 28
  private static let pullInInset: CGFloat = 56
  /// How far above and below the panel a dragged row still drops in the list.
  private static let listDropSlop: CGFloat = 12
  /// How near the list's top or bottom edge a row dragged within it scrolls
  /// it, and how fast at the edge, in points a second.
  private static let autoscrollZone: CGFloat = 36
  private static let autoscrollSpeed: CGFloat = 600
  /// How long the pool under the glass takes to follow a new measure of the
  /// page.
  private static let relightDuration: TimeInterval = 0.2
  /// How long the pointer rests on an open pin before its bead comes out.
  private static let pinDwell: TimeInterval = 0.12
  /// How long a typed tab number waits for another digit, when one could
  /// follow it.
  private static let numberTimeout: TimeInterval = 0.6
  /// How long a deleted shelf can be undone.
  private static let undoDuration: TimeInterval = 5

  private let model = TabOverlayModel()
  /// Holds everything but the downloads, which sinks behind their open list.
  private let stage = TabOverlayStage()
  private let hostingView: NSHostingView<TabOverlayView>
  private let addressBubble = RimmedGlassView(rimWidth: GlassCapsule.rimWidth)
  private let addressButton = TabOverlay.makeAddressButton()
  private let extensionsBubble = RimmedGlassView(
    rimWidth: GlassCapsule.rimWidth)
  private let downloadsBubble = DownloadsBubble()
  private let shelfBar = ShelfBar()
  /// Over everything, for a row dragged to the shelf bar.
  private let dragHostingView: TabDragHostingView
  private let isIncognito: Bool
  /// All the window's tabs; the panel lists those that aren't pins'.
  private var tabs: [FiberTabState] = []
  /// The window's split, whose right tab the spot has, apart from the list.
  private var split: SplitPair?
  private var isSpotPressed = false
  /// Scrolls the list while a row's dragged near its edge.
  private var autoscroll: Timer?
  /// Where the fingers have scrolled the list to, before rubber-banding.
  private var dragOffset: CGFloat = 0
  private var pressedRowID: TabListRow.ID?
  private var pressedRowPoint: CGPoint?
  private var pressedCloseButtonRowID: TabListRow.ID?
  /// Set once the window has shelves, which an Incognito window never does.
  private var hasShelves = false
  /// The profile's shelves; the bar and list leave out one being deleted.
  private var shelves: [FiberShelfState] = []
  /// A shelf the user deleted, which the bar's button can undo for a while
  /// before the browser hears of it.
  private var pendingShelfRemoval: (shelfID: String, removal: DispatchWorkItem)?
  /// The page whose tab its row's button just closed. The button, a trash can
  /// now, doesn't take a click until the pointer has left it.
  private var disarmedPageID: String?
  private var pressedPin: (pinID: String, point: CGPoint, part: PinPart)?
  /// Brings out the bead of the open pin under the pointer, once the pointer
  /// has rested on it, so that sweeping across a row doesn't ripple it.
  private var pendingBead: DispatchWorkItem?
  private var pendingBeadPinID: String?
  /// The pin whose bead took its tab back to the pinned page, until the page
  /// is there, so the bead turns to Close on the click rather than later.
  private var resettingPinID: String?
  /// Where the pointer was as the overlay opened, in screen coordinates,
  /// until it moves. What opened under it wasn't pointed at.
  private var restingPointer: CGPoint?
  /// Set once the window has its first pins, which appear without a flourish.
  private var hasPins = false
  /// The pins the list is below, and whose tabs it leaves out. They catch up
  /// with pins leaving once those have popped out, so the list waits to
  /// change.
  private var panelPins: [FiberPinState] = []
  private var isPanelCatchUpPending = false
  /// What stays put while the overlay is open, so that what the pointer just
  /// acted on doesn't move (see PanelHold).
  private var hold: PanelHold?
  /// From when it starts to close until it has faded out, it shows the tabs,
  /// pins and address it closed with, and the window's wait here.
  private var isClosing = false
  private var heldAddress: String?
  private var heldTabs: (tabs: [FiberTabState], activeTabID: Int)?
  private var heldPins: [FiberPinState]?
  private var heldDownloads: [FiberDownloadState]?
  private var heldShelves: [FiberShelfState]?
  private var heldSplit: SplitPair??
  /// Its fade out as it closes, which waits for what's on it to leave.
  private var pendingFadeOut: DispatchWorkItem?
  /// Counts its closings, so that a fade out from one cut short does nothing.
  private var closings = 0
  /// A tab number typed with Option that another digit could still lengthen,
  /// and the switch to its tab once none comes.
  private var typedNumber: Int?
  private var pendingNumberPick: DispatchWorkItem?

  init(isIncognito: Bool) {
    self.isIncognito = isIncognito
    hostingView = NSHostingView(rootView: TabOverlayView(model: model))
    dragHostingView = TabDragHostingView(rootView: TabDragView(model: model))
    super.init(frame: .zero)
    wantsLayer = true
    isHidden = true
    alphaValue = 0
    hostingView.sizingOptions = []
    // The model's coordinates are the view's, title bar included.
    hostingView.safeAreaRegions = []
    addSubview(stage)
    stage.content.addSubview(hostingView)
    for bubble in [addressBubble, extensionsBubble] {
      bubble.cornerRadius = GlassCapsule.height / 2
      stage.content.addSubview(bubble)
    }
    addressButton.target = self
    addressButton.action = #selector(addressClicked(_:))
    addressBubble.contentView = Self.capsuleContent(
      addressButton, fillingWidth: true)
    extensionsBubble.contentView = Self.capsuleContent(
      extensionsBar, fillingWidth: false)
    // Pinning an extension widens its capsule.
    extensionsBar.onResize = { [weak self] in self?.layoutPanel() }
    addSubview(downloadsBubble)
    downloadsBubble.onAction = { [weak self] action in
      self?.onDownloadAction(action)
    }
    downloadsBubble.onResize = { [weak self] in self?.layoutPanel() }
    downloadsBubble.onExpand = { [weak self] isExpanded, duration in
      self?.stage.setSunk(isExpanded, duration: duration)
    }
    configureShelfBar()
    dragHostingView.sizingOptions = []
    dragHostingView.safeAreaRegions = []
    addSubview(dragHostingView)
    downloadsBubble.onGlassChange = { [weak self] in
      guard let self else {
        return
      }
      self.model.downloadsFrame = self.downloadsBubble.glassFrame
      self.model.downloadsCornerRadius = self.downloadsBubble.glassCornerRadius
    }
    setAddress("")
    model.onSelect = { [weak self] rowID in self?.pick(rowID) }
    model.onClose = { [weak self] rowID in self?.closeRow(rowID) }
    model.onCloseTab = { [weak self] tabID in self?.onClose(tabID) }
    model.onOpenPin = { [weak self] pinID in self?.openPin(pinID) }
    model.onUnpin = { [weak self] pinID in self?.onUnpin(pinID) }
    model.onResetPin = { [weak self] pinID in self?.onResetPin(pinID) }
    model.onOpenSplit = { [weak self] in self?.openSplitTab() }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [
          .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow,
          .inVisibleRect,
        ],
        owner: self))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // MARK: Showing

  /// Fades the overlay in, with the keyboard, and the active tab (or its pin)
  /// selected.
  func open() {
    guard !isOpen else {
      return
    }
    downloadsBubble.isOverlayOpen = true
    stopClosing()
    isOpen = true
    downloadsBubble.setExpanded(false, animated: false)
    if downloadsBubble.isShown {
      onDownloadsShown()
    }
    // On the active tab's list, which it shows as it fades in.
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      shelfBar.select(segment(ofTabWithID: model.activeTabID), animated: false)
      updateListedTabs()
    }
    model.selection = initialSelection
    model.closeButton = nil
    hideBead()
    model.showsNumbers = Self.isOptionOnly(NSEvent.modifierFlags)
    optionDidChange(isHeld: model.showsNumbers)
    restingPointer = NSEvent.mouseLocation
    hold = nil
    layoutPanel()
    revealSelection(animated: false)
    isHidden = false
    model.isOpen = true
    moveBubbles()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = PaletteView.fadeInDuration
      animator().alphaValue = 1
    }
    window?.makeFirstResponder(self)
    onShowOrHide()
  }

  /// Plays the overlay's opening back, quicker, then fades it out. For what
  /// opens in its place, it fades out at once, even partway through closing.
  func close(forReplacement: Bool = false) {
    if isOpen {
      isOpen = false
      downloadsBubble.isOverlayOpen = false
      isClosing = true
      closings += 1
      model.isOpen = false
      moveBubbles()
      pressedPin = nil
      isSpotPressed = false
      model.pinDrag = nil
      model.tabDrag = nil
      stopAutoscroll()
      shelfBar.setDropTarget(nil)
      shelfBar.endRename(keep: true)
      commitShelfRemoval()
      hideBead()
      cancelTypedNumber()
      model.showsNumbers = false
      if window?.firstResponder === self {
        window?.makeFirstResponder(nil)
      }
    } else if !forReplacement || pendingFadeOut == nil {
      return
    }
    pendingFadeOut?.cancel()
    pendingFadeOut = nil
    let delay =
      forReplacement
      ? 0 : TabOverlayMotion.fadeOutDelay(span: model.motionSpan)
    guard delay > 0 else {
      fadeOut()
      return
    }
    let fadeOut = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.fadeOut()
      }
    }
    pendingFadeOut = fadeOut
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SlowMotion.duration(delay), execute: fadeOut)
  }

  private func fadeOut() {
    pendingFadeOut = nil
    let closing = closings
    NSAnimationContext.runAnimationGroup { context in
      context.duration = PaletteView.fadeOutDuration
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.isClosing, self.closings == closing else {
          return
        }
        self.isHidden = true
        self.stopClosing()
      }
    }
    onShowOrHide()
  }

  /// Faded out or opened again, it catches up with the window.
  private func stopClosing() {
    pendingFadeOut?.cancel()
    pendingFadeOut = nil
    guard isClosing else {
      return
    }
    isClosing = false
    if let address = heldAddress {
      heldAddress = nil
      setAddress(address)
    }
    if let pins = heldPins {
      heldPins = nil
      setPins(pins)
    }
    if let (tabs, activeTabID) = heldTabs {
      heldTabs = nil
      setTabs(tabs, activeTabID: activeTabID)
    }
    if let downloads = heldDownloads {
      heldDownloads = nil
      setDownloads(downloads)
    }
    if let shelves = heldShelves {
      heldShelves = nil
      setShelves(shelves)
    }
    if let split = heldSplit {
      heldSplit = nil
      setSplit(split)
    }
  }

  /// The address and extensions come and go with the pins (see
  /// TabOverlayMotion), from the left beside the panel, or from above like
  /// the pins when above them; the downloads and shelves from below, with the
  /// panel's wave.
  private func moveBubbles() {
    let offset =
      model.areBubblesBeside
      ? CGSize(width: -TabOverlayMotion.sideTravel, height: 0)
      : CGSize(width: 0, height: -TabOverlayMotion.travel)
    for bubble in [addressBubble, extensionsBubble] {
      TabOverlayMotion.move(
        bubble, from: offset, isOpening: isOpen,
        delay: model.motionDelay(ofBubble: bubble.frame),
        span: model.motionSpan)
    }
    let below = CGSize(width: 0, height: TabOverlayMotion.travel)
    TabOverlayMotion.move(
      downloadsBubble, from: below, isOpening: isOpen,
      delay: model.motionDelay(belowPanel: model.downloadsFrame),
      span: model.motionSpan)
    TabOverlayMotion.move(
      shelfBar, from: below, isOpening: isOpen,
      delay: model.motionDelay(belowPanel: model.shelfBarFrame),
      span: model.motionSpan)
  }

  /// How light the page under the overlay is, in CIE L*: the darker, the more
  /// black pools under the glass (see Dimming).
  func setPageLightness(_ lightness: Double) {
    withAnimation(.easeInOut(duration: Self.relightDuration).slowMotion) {
      model.pageLightness = lightness
    }
  }

  /// Shows the page's short address (usually just its host), or a prompt when
  /// there's none, as on the New Tab page.
  func setAddress(_ address: String) {
    guard !isClosing else {
      heldAddress = address
      return
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingMiddle
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let color = address.isEmpty ? NSColor.tertiaryLabelColor : .labelColor
    let title = NSMutableAttributedString()
    if isIncognito {
      // Like Safari's Private Browsing. An attachment's symbol doesn't take
      // the text's color.
      let symbol = NSTextAttachment()
      symbol.image = NSImage(
        systemSymbolName: "mustache", accessibilityDescription: "Incognito"
      )?.withSymbolConfiguration(
        .init(pointSize: font.pointSize, weight: .medium)
          .applying(.init(paletteColors: [color])))
      title.append(NSAttributedString(attachment: symbol))
      title.append(NSAttributedString(string: " "))
    }
    title.append(
      NSAttributedString(
        string: address.isEmpty ? "Search or enter address" : address))
    title.addAttributes(
      [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
      range: NSRange(location: 0, length: title.length))
    addressButton.attributedTitle = title
    layoutPanel()
  }

  // MARK: Tabs and pins

  func setTabs(_ tabs: [FiberTabState], activeTabID: Int) {
    guard !isClosing else {
      heldTabs = (tabs, activeTabID)
      return
    }
    self.tabs = tabs
    model.activeTabID = activeTabID
    updateListedTabs()
  }

  func setPins(_ pins: [FiberPinState]) {
    guard !isClosing else {
      heldPins = pins
      return
    }
    let countChanged = pins.count != model.pins.count
    if hasPins, isOpen {
      burst(from: model.pins, to: pins)
    }
    hasPins = true
    let arePinsLeaving = pins.count < model.pins.count
    model.pins = pins
    if let pinID = resettingPinID,
      pins.first(where: { $0.pinID == pinID }).map({
        $0.tabID == 0 || $0.isAtPinnedURL
      }) ?? true
    {
      resettingPinID = nil
    }
    // A pin's bead goes in with its tab, and turns between Back and Close as
    // its tab leaves or comes back to the pinned page.
    if let bead = model.pinBead {
      if let pin = pins.first(where: { $0.pinID == bead.pinID }),
        pin.tabID != 0
      {
        showBead(of: pin, fromKeyboard: bead.isFromKeyboard)
      } else {
        hideBead()
      }
    }
    if case .pin(let pinID)? = model.selection,
      !pins.contains(where: { $0.pinID == pinID })
    {
      model.selection = initialSelection
    }
    if arePinsLeaving, isOpen {
      schedulePanelCatchUp()
    } else if !isPanelCatchUpPending {
      catchUpPanel()
    }
    if countChanged {
      updatePinToolTips()
    }
  }

  func setDownloads(_ downloads: [FiberDownloadState]) {
    guard !isClosing else {
      heldDownloads = downloads
      return
    }
    downloadsBubble.setDownloads(downloads)
  }

  func setShelves(_ shelves: [FiberShelfState]) {
    guard !isClosing else {
      heldShelves = shelves
      return
    }
    hasShelves = true
    self.shelves = shelves
    updateShelves()
  }

  func setSplit(_ split: SplitPair?) {
    guard !isClosing else {
      heldSplit = .some(split)
      return
    }
    self.split = split
    if case .split? = model.selection, split == nil {
      model.selection = initialSelection
    }
    updateListedTabs()
  }

  // MARK: Shelves

  private func configureShelfBar() {
    stage.content.addSubview(shelfBar)
    shelfBar.onSelect = { [weak self] segment in self?.showSegment(segment) }
    shelfBar.onAdd = { [weak self] in self?.addShelf() }
    shelfBar.onUndo = { [weak self] in self?.undoShelfRemoval() }
    shelfBar.onRename = { [weak self] shelfID, name in
      self?.onRenameShelf(shelfID, name)
    }
    shelfBar.onMenu = { [weak self] shelf, event in
      self?.onShelfMenu(shelf, event)
    }
    shelfBar.onResize = { [weak self] in self?.layoutPanel() }
    shelfBar.onRenameEnd = { [weak self] in
      guard let self, self.isOpen else {
        return
      }
      self.window?.makeFirstResponder(self)
    }
  }

  /// The bar and list show the shelves but one being deleted.
  private func updateShelves() {
    shelfBar.setShelves(
      shelves.filter { $0.shelfID != pendingShelfRemoval?.shelfID })
    updateListedTabs()
  }

  /// The list the tab is in: its shelf's, if it's a shelf page's, or Home.
  private func segment(ofTabWithID tabID: Int) -> ShelfSegment {
    shelfBar.shelves.first { shelf in
      shelf.pages.contains { $0.tabID != 0 && $0.tabID == tabID }
    }.map { .shelf($0.shelfID) } ?? .home
  }

  /// Lists `segment`'s tabs, with the active one selected if it's among
  /// them, or else the first.
  private func showSegment(_ segment: ShelfSegment) {
    guard segment != shelfBar.segment else {
      return
    }
    holdShelfBar()
    shelfBar.select(segment, animated: true)
    disarmedPageID = nil
    setScrollOffset(0)
    updateListedTabs()
    model.selection = model.rows.isEmpty ? nil : initialSelection
    revealSelection(animated: false)
  }

  /// Left and Right go through the segments, from a row or none, not a pin.
  private func stepSegment(by step: Int) -> Bool {
    guard hasShelves, !(model.selection?.isPin ?? false),
      let index = shelfBar.segments.firstIndex(of: shelfBar.segment)
    else {
      return false
    }
    let next = index + step
    if shelfBar.segments.indices.contains(next) {
      showSegment(shelfBar.segments[next])
    }
    return true
  }

  /// Switching shelves, or dropping a row on one, keeps the bar where it is,
  /// and the list fills up from it.
  private func holdShelfBar() {
    if !model.shelfBarFrame.isEmpty {
      hold = .bar(model.shelfBarFrame.minY)
    }
  }

  /// Closing from the list keeps the rows where they are instead.
  private func holdPanelTop() {
    if hold?.barTop != nil {
      hold = .top(model.panelFrame.minY)
    }
  }

  private func addShelf() {
    commitShelfRemoval()
    guard let shelfID = onAddShelf() else {
      return
    }
    showSegment(.shelf(shelfID))
    shelfBar.beginRename(shelfID)
  }

  /// Puts a field over the shelf's segment, with its name selected.
  func beginRename(_ shelfID: String) {
    if isOpen {
      shelfBar.beginRename(shelfID)
    }
  }

  /// Hides the shelf, and deletes it once the bar's button can no longer
  /// undo it: after a while, or as the overlay closes.
  func deleteShelf(_ shelfID: String) {
    commitShelfRemoval()
    guard let shelf = shelves.first(where: { $0.shelfID == shelfID }) else {
      return
    }
    holdShelfBar()
    let removal = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.commitShelfRemoval() }
    }
    pendingShelfRemoval = (shelfID, removal)
    shelfBar.setUndoName(shelf.name)
    updateShelves()
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.undoDuration, execute: removal)
  }

  private func commitShelfRemoval() {
    guard let (shelfID, removal) = pendingShelfRemoval else {
      return
    }
    removal.cancel()
    pendingShelfRemoval = nil
    shelfBar.setUndoName(nil)
    onRemoveShelf(shelfID)
  }

  /// Edit › Undo (Command-Z) brings back a shelf just deleted.
  @objc func undo(_ sender: Any?) {
    undoShelfRemoval()
  }

  private func undoShelfRemoval() {
    guard let (_, removal) = pendingShelfRemoval else {
      return
    }
    removal.cancel()
    pendingShelfRemoval = nil
    shelfBar.setUndoName(nil)
    holdShelfBar()
    updateShelves()
  }

  /// A row's close button: a tab closes, a shelf page's leaving its row, and
  /// a shelf page without a tab is removed.
  private func closeRow(_ rowID: TabListRow.ID) {
    guard let row = model.rows.first(where: { $0.id == rowID }) else {
      return
    }
    holdPanelTop()
    switch (row.tabID, rowID) {
    case (let tabID?, .page(let pageID)):
      disarmedPageID = pageID
      onClose(tabID)
    case (let tabID?, .tab):
      onClose(tabID)
    case (nil, .page(let pageID)):
      onRemoveShelfPage(pageID)
    case (nil, .tab):
      break
    }
  }

  private func removeSelectedPage() {
    guard case .row(.page(let pageID))? = model.selection else {
      NSSound.beep()
      return
    }
    holdPanelTop()
    onRemoveShelfPage(pageID)
  }

  private func drop(_ drag: TabDrag) {
    switch drag.target {
    case .list(let index)?:
      move(drag.rowID, to: index)
    case .shelf(let segment)?:
      holdShelfBar()
      let shelfID: String
      if case .shelf(let id) = segment {
        shelfID = id
      } else {
        shelfID = ""
      }
      switch drag.rowID {
      case .page(let pageID):
        onMoveShelfPage(pageID, shelfID)
      case .tab(let tabID) where !shelfID.isEmpty:
        onMoveTabToShelf(tabID, shelfID)
      case .tab:
        break
      }
    case .split?:
      guard let leftTabID = splitLeftTab(for: drag.rowID) else {
        break
      }
      switch drag.rowID {
      case .tab(let tabID):
        onSplit(tabID, leftTabID)
      case .page(let pageID):
        onSplitCopy(pageID, leftTabID)
      }
    case nil:
      break
    }
  }

  /// Moves the row to `index` among the others: a tab before the tab there,
  /// or a shelf's page to that place on its shelf.
  private func move(_ rowID: TabListRow.ID, to index: Int) {
    guard let from = model.rows.firstIndex(where: { $0.id == rowID }),
      from != index
    else {
      return
    }
    switch rowID {
    case .tab(let tabID):
      let others = model.rows.filter { $0.id != rowID }
      onMoveTab(
        tabID, others.indices.contains(index) ? others[index].tabID ?? 0 : 0)
    case .page(let pageID):
      onMovePin(pageID, index)
    }
  }

  /// Home's tabs: those that aren't pins' or shelf pages'.
  private var homeTabs: [FiberTabState] {
    let pinTabIDs = Set(panelPins.map(\.tabID))
    let pageTabIDs = Set(shelfBar.shelves.flatMap(\.pages).map(\.tabID))
    return tabs.filter {
      !pinTabIDs.contains($0.tabID) && !pageTabIDs.contains($0.tabID)
    }
  }

  /// The tab a row's tab would go on the right of, dropped on the split's
  /// spot, or for a shelf page, its copy.
  private func splitLeftTab(for rowID: TabListRow.ID) -> Int? {
    switch rowID {
    case .tab(let tabID): splitLeftTab(beside: tabID)
    case .page: splitLeftTab(beside: nil)
    }
  }

  /// The same for the tab `tabID`, or a pin's or shelf page's copy for nil.
  private func splitLeftTab(beside tabID: Int?) -> Int? {
    SplitPair.leftTab(
      beside: tabID, in: split, tabs: tabs, activeTabID: model.activeTabID)
  }

  /// A pressed row dragged far enough lifts, to a new place in the list, or
  /// off it, for the shelf bar or the split's spot.
  private func dragRow(to point: CGPoint) -> Bool {
    guard let rowID = pressedRowID, let start = pressedRowPoint,
      let index = model.rows.firstIndex(where: { $0.id == rowID })
    else {
      return false
    }
    guard
      model.tabDrag != nil
        || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold
    else {
      return true
    }
    let grabOffset =
      model.tabDrag?.grabOffset
      ?? model.listContentY(at: start) - TabListLayout.rowCenter(index)
      + TabListLayout.rowHeight / 2
    let target = dropTarget(
      for: rowID, at: point, grabOffset: grabOffset,
      isLifted: model.tabDrag == nil || model.liftedRowTop != nil)
    model.closeButton = nil
    model.tabDrag = TabDrag(
      rowID: rowID, grabOffset: grabOffset, point: point, target: target)
    shelfBar.setDropTarget(target?.segment)
    updateAutoscroll()
    return true
  }

  /// Where a row dragged to `point` would go: the split's spot, a shelf's
  /// segment, or a place in the list, if any of them takes it. `isLifted` is
  /// whether it's within the list now.
  private func dropTarget(
    for rowID: TabListRow.ID, at point: CGPoint, grabOffset: CGFloat,
    isLifted: Bool
  ) -> TabDropTarget? {
    if splitLeftTab(for: rowID) != nil,
      SplitSpotLayout.takesDrop(at: point, frame: model.splitSpotFrame)
    {
      return .split
    }
    if hasShelves, let segment = shelfBar.segment(forDropAt: point),
      segment != shelfBar.segment
    {
      return .shelf(segment)
    }
    let list = model.panelFrame.insetBy(
      dx: isLifted ? Self.pullOutInset : Self.pullInInset,
      dy: -Self.listDropSlop)
    guard model.rows.count > 1, list.contains(point) else {
      return nil
    }
    return .list(
      model.dropIndex(
        forLiftedTop: model.liftedRowTop(at: point, grabOffset: grabOffset)))
  }

  /// While a row's lifted within the list near its top or bottom edge, the
  /// list scrolls, faster nearer the edge.
  private func updateAutoscroll() {
    guard autoscrollStep() != 0 else {
      stopAutoscroll()
      return
    }
    guard autoscroll == nil else {
      return
    }
    let interval: TimeInterval = 1 / 60
    autoscroll = Timer.scheduledTimer(withTimeInterval: interval, repeats: true)
    { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else {
          return
        }
        let step = self.autoscrollStep() * interval
        guard step != 0 else {
          self.stopAutoscroll()
          return
        }
        self.setScrollOffset(
          self.clamp(
            self.model.scrollOffset + step, to: self.model.scrollRange))
        self.retargetDrag()
      }
    }
  }

  /// How fast the list scrolls for the lifted row, in points a second, up the
  /// list for negative.
  private func autoscrollStep() -> CGFloat {
    guard let drag = model.tabDrag, case .list = drag.target,
      model.scrollRange.upperBound > 0
    else {
      return 0
    }
    let list = model.listRect.offsetBy(
      dx: model.panelFrame.minX, dy: model.panelFrame.minY)
    let zone = Self.autoscrollZone
    let intoTop = list.minY + zone - drag.point.y
    let intoBottom = drag.point.y - (list.maxY - zone)
    if intoTop > 0, model.scrollOffset > model.scrollRange.lowerBound {
      return -Self.autoscrollSpeed * min(intoTop / zone, 1)
    }
    if intoBottom > 0, model.scrollOffset < model.scrollRange.upperBound {
      return Self.autoscrollSpeed * min(intoBottom / zone, 1)
    }
    return 0
  }

  private func stopAutoscroll() {
    autoscroll?.invalidate()
    autoscroll = nil
  }

  /// The dragged row's target again, for the list scrolled under it.
  private func retargetDrag() {
    guard var drag = model.tabDrag else {
      return
    }
    drag.target = dropTarget(
      for: drag.rowID, at: drag.point, grabOffset: drag.grabOffset,
      isLifted: model.liftedRowTop != nil)
    model.tabDrag = drag
  }

  /// A flourish where each pin that came or went is, or was.
  private func burst(from old: [FiberPinState], to new: [FiberPinState]) {
    let oldIDs = Set(old.map(\.pinID))
    let newIDs = Set(new.map(\.pinID))
    let changed =
      old.enumerated().filter { !newIDs.contains($0.element.pinID) }
      + new.enumerated().filter { !oldIDs.contains($0.element.pinID) }
    guard !changed.isEmpty else {
      return
    }
    let bursts = changed.map { index, pin in
      PinBurst(
        origin: PinGridLayout.origin(of: index, width: model.gridWidth),
        color: pin.favicon?.burstColor)
    }
    model.pinBursts += bursts
    let ids = Set(bursts.map(\.id))
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SlowMotion.duration(PinBurstView.duration)
    ) { [weak self] in
      MainActor.assumeIsolated {
        self?.model.pinBursts.removeAll { ids.contains($0.id) }
      }
    }
  }

  private func schedulePanelCatchUp() {
    guard !isPanelCatchUpPending else {
      return
    }
    isPanelCatchUpPending = true
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SlowMotion.duration(PinGridLayout.popOutDuration)
    ) { [weak self] in
      MainActor.assumeIsolated {
        self?.isPanelCatchUpPending = false
        self?.catchUpPanel()
      }
    }
  }

  private func catchUpPanel() {
    panelPins = model.pins
    model.panelPinCount = panelPins.count
    updateListedTabs()
  }

  /// Home's tabs are those that aren't pins' or shelf pages', but for the one
  /// in the split's spot; a shelf lists its pages, as their tabs are if
  /// they're open.
  private func updateListedTabs() {
    let previous = model.rows
    model.split = split
    model.splitTab = split.flatMap { split in
      tabs.first { $0.tabID == split.rightTabID }
    }
    switch shelfBar.segment {
    case .home:
      model.rows = homeTabs.filter { $0.tabID != split?.rightTabID }
        .map(TabListRow.init(tab:))
      model.listedShelfName = nil
    case .shelf(let shelfID):
      let shelf = shelfBar.shelves.first { $0.shelfID == shelfID }
      model.rows = (shelf?.pages ?? []).map { page in
        TabListRow(
          page: page,
          tab: page.tabID == 0 ? nil : tabs.first { $0.tabID == page.tabID })
      }
      model.listedShelfName = shelf?.name
    }
    // With the split's right tab active, its left shows too.
    let activeTabID =
      split?.rightTabID == model.activeTabID
      ? split?.leftTabID : model.activeTabID
    model.activeRowID = model.rows.first { $0.tabID == activeTabID }?.id
    if let pageID = disarmedPageID,
      !model.rows.contains(where: { $0.id == .page(pageID) })
    {
      disarmedPageID = nil
    }
    // A selected row that's gone, closed say, leaves the selection to the one
    // in its place.
    if case .row(let rowID)? = model.selection,
      !model.rows.contains(where: { $0.id == rowID })
    {
      let index = previous.firstIndex { $0.id == rowID } ?? 0
      model.selection =
        model.rows.isEmpty
        ? model.pins.first.map { .pin($0.pinID) }
        : .row(model.rows[min(index, model.rows.count - 1)].id)
    }
    layoutPanel()
    // Clicking a close button moves the rows under the pointer.
    if model.closeButton != nil, let window {
      hover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
  }

  /// The active tab's pin, spot or row.
  private var initialSelection: TabOverlaySelection? {
    let activeTabID = model.activeTabID
    if let pin = model.pins.first(where: {
      $0.tabID != 0 && $0.tabID == activeTabID
    }) {
      return .pin(pin.pinID)
    }
    if split?.rightTabID == activeTabID {
      return .split
    }
    if let rowID = model.activeRowID {
      return .row(rowID)
    }
    return (model.rows.first?.id).map { .row($0) }
      ?? (model.pins.first?.pinID).map { .pin($0) }
  }

  // MARK: Layout (flipped: y grows down from the window's top)

  override var isFlipped: Bool { true }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    stage.frame = bounds
    hostingView.frame = bounds
    downloadsBubble.frame = bounds
    shelfBar.frame = bounds
    dragHostingView.frame = bounds
    hold = nil
    layoutPanel(animated: false)
  }

  /// The panel as wide as the command palette's, as tall as fits, with what's
  /// above and below it a little above the window's middle; the address and
  /// extensions to its left (or above if narrow), the split's spot to its
  /// right (or above, at the end, if narrower), the downloads under it.
  private func layoutPanel(animated: Bool = true) {
    guard bounds.width > 0 else {
      return
    }
    let (x, width, _) = PaletteView.panelPlacement(in: bounds.size)
    let height = GlassCapsule.height
    let padding = 2 * (GlassCapsule.rimWidth + GlassCapsule.endInset)
    var addressWidth = min(
      addressButton.fittingSize.width + padding, Self.maxAddressWidth)
    let extensionsWidth = extensionsBar.fittingSize.width + padding
    let columnEnd = x - Self.bubbleSpacing
    let isBeside =
      columnEnd - max(addressWidth, extensionsWidth) >= Self.bubbleMargin
    let spot = SplitSpotLayout.diameter
    let isSpotBeside =
      bounds.width - (x + width + Self.bubbleSpacing + spot)
      >= Self.bubbleMargin
    let pinsHeight = model.pinsHeight(width: width)
    let above = pinsHeight + (isBeside ? 0 : height + Self.bubbleSpacing)
    let footerHeight = TabOverlayModel.footerHeight
    let below =
      footerHeight
      + (downloadsBubble.isShown || hasShelves
        ? DownloadsLayout.spacing + GlassCapsule.height : 0)
    let highest = PaletteView.minTop + above
    var listHeight = min(
      model.listContentHeight,
      max(bounds.height - PaletteView.bottomMargin - below - highest, 0))
    let top: CGFloat
    if let barTop = hold?.barTop,
      barTop - DownloadsLayout.spacing - footerHeight >= highest
    {
      listHeight = min(
        listHeight, barTop - DownloadsLayout.spacing - footerHeight - highest)
      top = barTop - DownloadsLayout.spacing - footerHeight - listHeight
    } else {
      let lowest = max(
        bounds.height - PaletteView.bottomMargin - below - listHeight, highest)
      let placed =
        ((bounds.height - above - below - listHeight) * Self.topShare)
        .rounded() + above
      top = min(max(hold?.top ?? placed, highest), lowest)
      if isOpen {
        hold = .top(top)
      }
    }
    model.areBubblesBeside = isBeside
    if isBeside {
      addressBubble.frame = NSRect(
        x: columnEnd - addressWidth, y: top, width: addressWidth,
        height: height)
      extensionsBubble.frame = NSRect(
        x: columnEnd - extensionsWidth,
        y: top + height + GlassCapsule.spacing, width: extensionsWidth,
        height: height)
    } else {
      let spotRoom = isSpotBeside ? 0 : spot + GlassCapsule.spacing
      addressWidth = max(
        min(
          addressWidth,
          width - extensionsWidth - GlassCapsule.spacing - spotRoom),
        0)
      addressBubble.frame = NSRect(
        x: x, y: top - above, width: addressWidth, height: height)
      extensionsBubble.frame = NSRect(
        x: x + addressWidth + GlassCapsule.spacing, y: top - above,
        width: extensionsWidth, height: height)
    }
    let bubbleFrames = [addressBubble.frame, extensionsBubble.frame]
    if bubbleFrames != model.bubbleFrames {
      model.bubbleFrames = bubbleFrames
    }
    // Level with the panel's top, or else at the end of the address's row
    // above it.
    let spotTop = isSpotBeside ? top : top - above
    let spotFrame = CGRect(
      x: isSpotBeside ? x + width + Self.bubbleSpacing : x + width - spot,
      y: spotTop + (height - spot) / 2, width: spot, height: spot)
    if spotFrame != model.splitSpotFrame {
      model.splitSpotFrame = spotFrame
      updatePinToolTips()
    }

    let frame = CGRect(
      x: x, y: top, width: width, height: footerHeight + listHeight)
    if frame != model.panelFrame {
      model.panelFrame = frame
      updatePinToolTips()
    }
    setScrollOffset(clamp(model.scrollOffset, to: model.scrollRange))
    let downloadsWidth = min(downloadsBubble.capsuleWidth, width)
    downloadsBubble.setCapsuleFrame(
      CGRect(
        x: frame.maxX - downloadsWidth, y: frame.maxY + DownloadsLayout.spacing,
        width: downloadsWidth, height: GlassCapsule.height),
      animated: animated && isOpen)
    layoutShelfBar(
      under: frame, downloadsWidth: downloadsBubble.isShown ? downloadsWidth : 0)
  }

  /// The shelf bar as wide as its segments, or as fits short of the
  /// downloads with its button after it, scrolling across if narrower.
  private func layoutShelfBar(under panel: CGRect, downloadsWidth: CGFloat) {
    guard hasShelves else {
      return
    }
    let room =
      panel.width - shelfBar.buttonWidth - GlassCapsule.spacing
      - (downloadsWidth > 0
        ? downloadsWidth + ShelfBarLayout.downloadsClearance : 0)
    shelfBar.place(
      at: CGPoint(x: panel.minX, y: panel.maxY + DownloadsLayout.spacing),
      width: max(min(shelfBar.contentWidth, room), ShelfBarLayout.height))
    if shelfBar.barFrame != model.shelfBarFrame
      || shelfBar.buttonFrame != model.shelfButtonFrame
    {
      model.shelfBarFrame = shelfBar.barFrame
      model.shelfButtonFrame = shelfBar.buttonFrame
    }
  }

  /// `view` in the middle of a capsule's glass, as wide as its ends allow if
  /// `fillingWidth`.
  private static func capsuleContent(_ view: NSView, fillingWidth: Bool)
    -> NSView
  {
    let content = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(view)
    var constraints = [
      view.centerYAnchor.constraint(equalTo: content.centerYAnchor)
    ]
    if fillingWidth {
      constraints += [
        view.leadingAnchor.constraint(
          equalTo: content.leadingAnchor, constant: GlassCapsule.endInset),
        view.trailingAnchor.constraint(
          equalTo: content.trailingAnchor, constant: -GlassCapsule.endInset),
      ]
    } else {
      constraints.append(
        view.centerXAnchor.constraint(equalTo: content.centerXAnchor))
    }
    NSLayoutConstraint.activate(constraints)
    return content
  }

  private static func makeAddressButton() -> NSButton {
    let button = NSButton(title: "", target: nil, action: nil)
    button.bezelStyle = .accessoryBarAction
    button.borderShape = .capsule
    button.showsBorderOnlyWhileMouseInside = true
    button.toolTip = "Search or enter address"
    button.setContentCompressionResistancePriority(
      .defaultLow, for: .horizontal)
    button.heightAnchor.constraint(equalToConstant: GlassCapsule.buttonSize)
      .isActive = true
    return button
  }

  @objc private func addressClicked(_ sender: Any?) {
    onAddressClick()
  }

  // MARK: Geometry

  private func location(of event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
  }

  /// Where `event` is on the panel and pins as they're laid out, while the
  /// downloads' open list sinks them (see TabOverlayStage).
  private func stageLocation(of event: NSEvent) -> CGPoint {
    stage.layoutPoint(drawnAt: location(of: event))
  }

  /// `point` from the panel's top-left corner.
  private func inPanel(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: point.x - model.panelFrame.minX, y: point.y - model.panelFrame.minY)
  }

  /// `point` in the pins' grid (see PinGridLayout).
  private func inPins(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x - model.pinsOrigin.x, y: point.y - model.pinsOrigin.y)
  }

  /// The pin at `point`, as it's shown.
  private func pin(at point: CGPoint) -> FiberPinState? {
    pinHit(at: point)?.pin
  }

  /// The pin at `point`, as it's shown, and which part of it.
  private func pinHit(at point: CGPoint) -> (pin: FiberPinState, part: PinPart)?
  {
    PinGridLayout.hit(
      at: inPins(point), count: model.pins.count, bead: model.beadIndex,
      width: model.gridWidth
    ).map { (model.pins[$0.index], $0.part) }
  }

  /// Whether `point` is on the panel, on or between the pins, or on the
  /// split's spot. A pin's bead can reach past the grid's edges.
  private func isOnPanelOrPins(_ point: CGPoint) -> Bool {
    model.panelFrame.contains(point)
      || PinGridLayout.covers(
        inPins(point), count: model.pins.count, width: model.gridWidth)
      || pinHit(at: point) != nil || isOnSpot(point)
  }

  private func isOnSpot(_ point: CGPoint) -> Bool {
    SplitSpotLayout.contains(point, frame: model.splitSpotFrame)
  }

  /// The row at `point`, where the list is scrolled to now.
  private func row(at point: CGPoint) -> TabListRow? {
    let point = inPanel(point)
    let list = model.listRect
    guard list.contains(point) else {
      return nil
    }
    let offset =
      point.y - list.minY + model.scrollOffset - TabListLayout.contentInset
    guard offset >= 0 else {
      return nil
    }
    let index = Int(offset / TabListLayout.rowStep)
    return model.rows.indices.contains(index) ? model.rows[index] : nil
  }

  /// The close button `point` is within reach of, where the list is scrolled
  /// to now.
  private func closeButton(near point: CGPoint) -> TabCloseButton? {
    let point = inPanel(point)
    let list = model.listRect
    guard list.contains(point) else {
      return nil
    }
    return TabListLayout.closeButton(
      near: CGPoint(x: point.x, y: point.y - list.minY + model.scrollOffset),
      in: model.rows.map(\.id), width: list.width)
  }

  /// The row whose close button is at `point`, if it's showing and takes a
  /// click.
  private func closeButtonRow(at point: CGPoint) -> TabListRow.ID? {
    guard let button = closeButton(near: point), button.isHovered,
      button.rowID == model.closeButton?.rowID,
      disarmedPageID.map({ button.rowID != .page($0) }) ?? true
    else {
      return nil
    }
    return button.rowID
  }

  /// Scrolls the least that shows the selected row whole.
  private func revealSelection(animated: Bool) {
    guard let rowID = model.selectedRowID,
      let row = model.rows.firstIndex(where: { $0.id == rowID })
    else {
      return
    }
    let top = CGFloat(row) * TabListLayout.rowStep
    let bottom =
      top + TabListLayout.rowHeight + 2 * TabListLayout.contentInset
      - model.listRect.height
    let offset = min(
      max(clamp(model.scrollOffset, to: model.scrollRange), bottom), top)
    setScrollOffset(
      offset, animation: animated ? .spring(duration: 0.25, bounce: 0) : nil)
  }

  private func setScrollOffset(_ offset: CGFloat, animation: Animation? = nil)
  {
    guard offset != model.scrollOffset else {
      return
    }
    withAnimation(animation?.slowMotion) {
      model.scrollOffset = offset
    }
  }

  // MARK: Tooltips

  /// A pin shows only its icon, so its title shows on hover, as the split's
  /// spot shows its tab's.
  private func updatePinToolTips() {
    removeAllToolTips()
    addToolTip(model.splitSpotFrame, owner: self, userData: nil)
    let pins = model.pinsOrigin
    var frames = model.pins.indices.map {
      PinGridLayout.frame(of: $0, width: model.gridWidth)
    }
    if let index = model.beadIndex {
      frames.append(PinGridLayout.beadFrame(of: index, width: model.gridWidth))
    }
    for frame in frames {
      addToolTip(
        frame.offsetBy(dx: pins.x, dy: pins.y), owner: self, userData: nil)
    }
  }

  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData data: UnsafeMutableRawPointer?
  ) -> String {
    if isOnSpot(point) {
      guard let tab = model.splitTab else {
        return "Drag a tab here to show it on the right"
      }
      return tab.title.isEmpty ? tab.url : tab.title
    }
    guard let (pin, part) = pinHit(at: point) else {
      return ""
    }
    switch part {
    case .bead:
      return model.pinBead?.action == .reset
        ? "Back to \(pin.url)" : "Close tab"
    case .bridge:
      return ""
    case .icon:
      return pin.title.isEmpty ? pin.url : pin.title
    }
  }

  // MARK: Keyboard

  /// While open, the window keeps the keyboard from the rest of it (see
  /// BrowserWindowController.tabOverlayKeepsKeyboard(from:)).
  override var acceptsFirstResponder: Bool { isOpen }

  /// Command-W closes the selection, not the tab behind the overlay.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isOpen,
      event.modifierFlags.intersection([.command, .shift, .option, .control])
        == .command,
      event.charactersIgnoringModifiers?.lowercased() == "w"
    else {
      return super.performKeyEquivalent(with: event)
    }
    closeSelection()
    return true
  }

  override func keyDown(with event: NSEvent) {
    guard Self.isOptionOnly(event.modifierFlags),
      let digit = event.characters(byApplyingModifiers: []).flatMap({
        Int($0)
      })
    else {
      cancelTypedNumber()
      interpretKeyEvents([event])
      return
    }
    if !event.isARepeat {
      type(digit)
    }
  }

  /// Letting go of Option switches to the tab whose number was being typed.
  override func flagsChanged(with event: NSEvent) {
    super.flagsChanged(with: event)
    let showsNumbers = isOpen && Self.isOptionOnly(event.modifierFlags)
    if !showsNumbers {
      pickTypedNumber()
    }
    model.showsNumbers = showsNumbers
    optionDidChange(isHeld: showsNumbers)
  }

  /// Switches to the tab whose number `digit` completes. While a longer
  /// number could start with it, its tab is selected for a moment instead.
  private func type(_ digit: Int) {
    pendingNumberPick?.cancel()
    pendingNumberPick = nil
    guard
      let (number, isComplete) = Self.tabNumber(
        typing: digit, after: typedNumber, count: model.rows.count)
    else {
      typedNumber = nil
      NSSound.beep()
      return
    }
    typedNumber = number
    guard !isComplete else {
      pickTypedNumber()
      return
    }
    select(.row(model.rows[number - 1].id))
    let pick = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.pickTypedNumber()
      }
    }
    pendingNumberPick = pick
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.numberTimeout, execute: pick)
  }

  /// The tab number `digit` makes typed after `typed`, of `count` tabs, and
  /// whether it's complete, no other number starting with it; nil if no tab
  /// has it.
  static func tabNumber(typing digit: Int, after typed: Int?, count: Int)
    -> (number: Int, isComplete: Bool)?
  {
    let number = (typed ?? 0) * 10 + digit
    guard number >= 1, number <= count else {
      return nil
    }
    return (number, number * 10 > count)
  }

  private func pickTypedNumber() {
    guard let number = typedNumber else {
      return
    }
    cancelTypedNumber()
    if model.rows.indices.contains(number - 1) {
      pick(model.rows[number - 1].id)
    }
  }

  private func cancelTypedNumber() {
    typedNumber = nil
    pendingNumberPick?.cancel()
    pendingNumberPick = nil
  }

  private static func isOptionOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
    flags.intersection([.command, .shift, .option, .control]) == .option
  }

  override func moveUp(_ sender: Any?) {
    moveSelection(.up)
  }

  override func moveDown(_ sender: Any?) {
    moveSelection(.down)
  }

  override func moveLeft(_ sender: Any?) {
    if !stepSegment(by: -1) {
      moveSelection(.left)
    }
  }

  override func moveRight(_ sender: Any?) {
    if !stepSegment(by: 1) {
      moveSelection(.right)
    }
  }

  override func deleteBackward(_ sender: Any?) {
    removeSelectedPage()
  }

  override func deleteForward(_ sender: Any?) {
    removeSelectedPage()
  }

  /// With Option held, the arrow keys still move across the pins, the bead
  /// following the selection, and Option-Return presses it.
  override func moveWordLeft(_ sender: Any?) {
    moveSelection(.left)
  }

  override func moveWordRight(_ sender: Any?) {
    moveSelection(.right)
  }

  override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
    guard let bead = model.pinBead, bead.isFromKeyboard,
      let pin = model.pins.first(where: { $0.pinID == bead.pinID })
    else {
      insertNewline(sender)
      return
    }
    // Held down, it doesn't go on to close the tab it took back.
    if NSApp.currentEvent?.isARepeat != true {
      press(.bead, of: pin)
    }
  }

  override func insertTab(_ sender: Any?) {
    stepSelection(by: 1)
  }

  override func insertBacktab(_ sender: Any?) {
    stepSelection(by: -1)
  }

  override func insertNewline(_ sender: Any?) {
    switch model.selection {
    case .split?:
      openSplitTab()
    case .pin(let pinID)?:
      openPin(pinID)
    case .row(let rowID)?:
      pick(rowID)
    case nil:
      onDismiss()
    }
  }

  override func cancelOperation(_ sender: Any?) {
    if downloadsBubble.isExpanded {
      downloadsBubble.setExpanded(false, animated: true)
    } else {
      onDismiss()
    }
  }

  private enum Direction {
    case up, down, left, right
  }

  private func moveSelection(_ direction: Direction) {
    guard let next = selection(after: model.selection, moving: direction)
    else {
      return
    }
    select(next)
  }

  /// Through the pins as a grid whose rows rise from the list, then the list's
  /// rows as a column.
  private func selection(
    after selection: TabOverlaySelection?, moving direction: Direction
  ) -> TabOverlaySelection? {
    let pins = model.pins
    let rows = model.rows
    let columns = PinGridLayout.columns(width: model.gridWidth)
    let topRowStart = (max(pins.count, 1) - 1) / columns * columns
    switch selection {
    case .split?:
      // Beside the list's top, as the pins' first row is above it.
      switch direction {
      case .up:
        return pins.first.map { .pin($0.pinID) }
      case .down, .left:
        return rows.first.map { .row($0.id) }
      case .right:
        return nil
      }
    case .pin(let pinID)?:
      guard let index = pins.firstIndex(where: { $0.pinID == pinID }) else {
        return initialSelection
      }
      switch direction {
      case .left, .right:
        let next = index + (direction == .left ? -1 : 1)
        return pins.indices.contains(next) ? .pin(pins[next].pinID) : nil
      case .up:
        return index >= topRowStart
          ? nil : .pin(pins[min(index + columns, pins.count - 1)].pinID)
      case .down:
        return index < columns
          ? rows.first.map { .row($0.id) } : .pin(pins[index - columns].pinID)
      }
    case .row(let rowID)?:
      guard let index = rows.firstIndex(where: { $0.id == rowID }) else {
        return initialSelection
      }
      switch direction {
      case .up where index == 0:
        return pins.first.map { .pin($0.pinID) }
      case .up:
        return .row(rows[index - 1].id)
      case .down:
        return index + 1 < rows.count ? .row(rows[index + 1].id) : nil
      case .left, .right:
        return nil
      }
    case nil:
      return initialSelection
    }
  }

  /// Tab and Shift-Tab go through the pins, the split's spot and the rows in
  /// reading order.
  private func stepSelection(by step: Int) {
    let items =
      model.pins.map { TabOverlaySelection.pin($0.pinID) }
      + (split != nil ? [.split] : []) + model.rows.map { .row($0.id) }
    guard let current = model.selection.flatMap(items.firstIndex(of:)) else {
      select(initialSelection)
      return
    }
    let next = current + step
    if items.indices.contains(next) {
      select(items[next])
    }
  }

  private func select(_ selection: TabOverlaySelection?) {
    guard selection != model.selection else {
      return
    }
    model.selection = selection
    optionDidChange(isHeld: model.showsNumbers)
    revealSelection(animated: true)
  }

  /// A pin's tab, if it's open, or the row's.
  private func closeSelection() {
    holdPanelTop()
    switch model.selection {
    case .pin(let pinID)?:
      if let pin = model.pins.first(where: { $0.pinID == pinID }),
        pin.tabID != 0
      {
        onClose(pin.tabID)
      }
    case .row(let rowID)?:
      // A shelf page without a tab is removed only with Delete.
      if let tabID = model.rows.first(where: { $0.id == rowID })?.tabID {
        onClose(tabID)
      }
    case .split?:
      if let split {
        onClose(split.rightTabID)
      }
    case nil:
      break
    }
  }

  /// A row's tab, or its shelf page's, opened.
  private func pick(_ rowID: TabListRow.ID) {
    guard let tabID = model.rows.first(where: { $0.id == rowID })?.tabID else {
      if case .page(let pageID) = rowID {
        onOpenShelfPage(pageID)
      }
      return
    }
    // The active tab outside the split goes beside its right tab.
    let isPaired = split.map { $0.contains(tabID) || !isHomeTab(tabID) } ?? true
    if tabID == model.activeTabID, isPaired {
      onDismiss()
    } else {
      onSelect(tabID)
    }
  }

  private func isHomeTab(_ tabID: Int) -> Bool {
    homeTabs.contains { $0.tabID == tabID }
  }

  private func openPin(_ pinID: String) {
    let isActive = model.pins.contains {
      $0.pinID == pinID && $0.tabID != 0 && $0.tabID == model.activeTabID
    }
    if isActive {
      onDismiss()
    } else {
      onOpenPin(pinID)
    }
  }

  /// The split's right tab, which shows it with the left.
  private func openSplitTab() {
    guard let split else {
      return
    }
    if split.rightTabID == model.activeTabID {
      onDismiss()
    } else {
      onSelect(split.rightTabID)
    }
  }

  // MARK: Pointer

  /// Everything but the address, extensions, downloads and shelves, which
  /// take their own clicks. The page under it takes none.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard isOpen, let view = super.hitTest(point) else {
      return nil
    }
    let isInBubble = [addressBubble, extensionsBubble, downloadsBubble, shelfBar]
      .contains { view.isDescendant(of: $0) }
    return isInBubble ? view : self
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    guard let window else {
      return
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(windowDidResignKey(_:)),
      name: NSWindow.didResignKeyNotification, object: window)
  }

  /// Option's release won't reach it once the window isn't key.
  @objc private func windowDidResignKey(_ notification: Notification) {
    hover(at: nil)
    cancelTypedNumber()
    model.showsNumbers = false
    optionDidChange(isHeld: false)
  }

  override func mouseMoved(with event: NSEvent) {
    hover(at: location(of: event))
  }

  override func mouseEntered(with event: NSEvent) {
    hover(at: location(of: event))
  }

  override func mouseExited(with event: NSEvent) {
    hover(at: nil)
  }

  override func mouseDown(with event: NSEvent) {
    let point = stageLocation(of: event)
    shelfBar.endRename(keep: true)
    // A click off the downloads' list closes it; on nothing else, that's all
    // it does.
    if downloadsBubble.isExpanded {
      downloadsBubble.setExpanded(false, animated: true)
      guard isOnPanelOrPins(point) else {
        return
      }
    }
    guard isOnPanelOrPins(point) else {
      onDismiss()
      return
    }
    if event.modifierFlags.contains(.control) {
      showMenu(for: event)
      return
    }
    if let (pin, part) = pinHit(at: point) {
      // A double-click's second click doesn't press the bead, which by then
      // may close the tab the first took back.
      if part != .bead || event.clickCount == 1 {
        pressedPin = (pin.pinID, point, part)
      }
      return
    }
    if isOnSpot(point) {
      isSpotPressed = true
      return
    }
    pressedCloseButtonRowID = closeButtonRow(at: point)
    if pressedCloseButtonRowID == nil {
      pressedRowID = row(at: point)?.id
      pressedRowPoint = point
    }
  }

  override func mouseDragged(with event: NSEvent) {
    if dragRow(to: stageLocation(of: event)) {
      return
    }
    guard let pressedPin, pressedPin.part == .icon,
      let from = model.pins.firstIndex(where: { $0.pinID == pressedPin.pinID })
    else {
      return
    }
    let point = stageLocation(of: event)
    let offset = CGSize(
      width: point.x - pressedPin.point.x,
      height: point.y - pressedPin.point.y)
    guard
      model.pinDrag != nil
        || hypot(offset.width, offset.height) >= Self.dragThreshold
    else {
      return
    }
    if model.pinDrag == nil {
      hideBead()
    }
    let origin = PinGridLayout.origin(of: from, width: model.gridWidth)
    let center = CGPoint(
      x: origin.x + PinGridLayout.diameter / 2 + offset.width,
      y: origin.y + PinGridLayout.diameter / 2 + offset.height)
    let isOverSplit =
      splitLeftTab(beside: nil) != nil
      && SplitSpotLayout.takesDrop(at: point, frame: model.splitSpotFrame)
    model.pinDrag = PinDrag(
      pinID: pressedPin.pinID, offset: offset,
      // Over the split's spot, the pins stay as they are.
      targetIndex: isOverSplit
        ? from
        : PinGridLayout.nearestIndex(
          to: center, count: model.pins.count, width: model.gridWidth),
      isOverSplit: isOverSplit)
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      pressedRowID = nil
      pressedRowPoint = nil
      pressedCloseButtonRowID = nil
      pressedPin = nil
      isSpotPressed = false
    }
    let point = stageLocation(of: event)
    if let drag = model.tabDrag {
      stopAutoscroll()
      shelfBar.setDropTarget(nil)
      // The browser moves the tab before this returns, so a row dropped in
      // the list settles into its new place from under the pointer.
      withAnimation(.spring(duration: 0.3, bounce: 0.15).slowMotion) {
        model.tabDrag = nil
        drop(drag)
      }
      hover(at: location(of: event))
      return
    }
    if isSpotPressed {
      if isOnSpot(point) {
        openSplitTab()
      }
      return
    }
    if let drag = model.pinDrag {
      // The browser reorders the pins before this returns, so the pin settles
      // into its new place from where it was dropped.
      if drag.isOverSplit, let leftTabID = splitLeftTab(beside: nil) {
        onSplitCopy(drag.pinID, leftTabID)
      } else if drag.targetIndex
        != model.pins.firstIndex(where: { $0.pinID == drag.pinID })
      {
        onMovePin(drag.pinID, drag.targetIndex)
      }
      model.pinDrag = nil
      hover(at: location(of: event))
      return
    }
    if let pressedPin {
      if let (pin, part) = pinHit(at: point), pin.pinID == pressedPin.pinID,
        part == pressedPin.part
      {
        press(part, of: pin)
      }
      return
    }
    if let rowID = pressedCloseButtonRowID {
      if closeButtonRow(at: point) == rowID {
        closeRow(rowID)
      }
      return
    }
    guard let rowID = row(at: point)?.id, rowID == pressedRowID else {
      return
    }
    pick(rowID)
  }

  override func rightMouseDown(with event: NSEvent) {
    downloadsBubble.setExpanded(false, animated: true)
    showMenu(for: event)
  }

  private func showMenu(for event: NSEvent) {
    let point = stageLocation(of: event)
    if let pin = pin(at: point) {
      onPinMenu(pin, event)
      return
    }
    if isOnSpot(point) {
      if split != nil {
        onSplitMenu(event)
      }
      return
    }
    switch row(at: point)?.id {
    case .tab(let tabID)?:
      onTabMenu(tabID, event)
    case .page(let pageID)?:
      if let shelf = shelfBar.shelves.first(where: {
        $0.pages.contains { $0.pinID == pageID }
      }), let page = shelf.pages.first(where: { $0.pinID == pageID }) {
        onShelfPageMenu(page, shelf, event)
      }
    case nil:
      break
    }
  }

  /// The selection follows the pointer onto a pin or a row, once it has
  /// moved. Nil for the pointer gone, or on the downloads over the rows.
  private func hover(at point: CGPoint?) {
    guard isOpen, restingPointer != NSEvent.mouseLocation else {
      return
    }
    restingPointer = nil
    let point = point.flatMap {
      downloadsBubble.glassFrame.contains($0)
        ? nil : stage.layoutPoint(drawnAt: $0)
    }
    let isDragging = model.pinDrag != nil || model.tabDrag != nil
    let hit = point.flatMap { isDragging ? nil : pinHit(at: $0) }
    if let point, !isDragging {
      if let (pin, _) = hit {
        model.selection = .pin(pin.pinID)
      } else if split != nil, isOnSpot(point) {
        model.selection = .split
      } else if let row = row(at: point) {
        model.selection = .row(row.id)
      }
    }
    hoverPin(hit)
    let button = isDragging ? nil : point.flatMap(closeButton(near:))
    if let pageID = disarmedPageID,
      button?.isHovered != true || button?.rowID != .page(pageID)
    {
      disarmedPageID = nil
    }
    if button != model.closeButton {
      model.closeButton = button
    }
  }

  /// An open pin the pointer rests on brings out its bead, which goes in as
  /// soon as the pointer leaves them. One Option brought out stays while it's
  /// held.
  private func hoverPin(_ hit: (pin: FiberPinState, part: PinPart)?) {
    if let bead = model.pinBead,
      bead.pinID == hit?.pin.pinID || bead.isFromKeyboard
    {
      if let hit, bead.pinID == hit.pin.pinID,
        model.focusedPinPart != hit.part
      {
        model.focusedPinPart = hit.part
      }
      return
    }
    guard let pin = hit?.pin, pin.tabID != 0 else {
      hideBead()
      return
    }
    guard pendingBead == nil || pendingBeadPinID != pin.pinID else {
      return
    }
    hideBead()
    let show = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.showBead(of: pin, fromKeyboard: false)
      }
    }
    pendingBead = show
    pendingBeadPinID = pin.pinID
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SlowMotion.duration(Self.pinDwell), execute: show)
  }

  /// Brings out `pin`'s bead, or updates the bead that's out.
  private func showBead(of pin: FiberPinState, fromKeyboard: Bool) {
    pendingBead?.cancel()
    pendingBead = nil
    let bead = PinBead(
      pinID: pin.pinID,
      action: pin.isAtPinnedURL || resettingPinID == pin.pinID
        ? .close : .reset,
      isFromKeyboard: fromKeyboard)
    guard bead != model.pinBead else {
      return
    }
    if model.pinBead?.pinID != pin.pinID {
      model.focusedPinPart = .icon
    }
    model.pinBead = bead
    updatePinToolTips()
  }

  private func hideBead() {
    pendingBead?.cancel()
    pendingBead = nil
    resettingPinID = nil
    guard model.pinBead != nil else {
      return
    }
    model.pinBead = nil
    model.focusedPinPart = nil
    updatePinToolTips()
  }

  /// While Option is held, the selected pin has its bead out, if its tab is
  /// open.
  private func optionDidChange(isHeld: Bool) {
    if isHeld, case .pin(let pinID)? = model.selection,
      let pin = model.pins.first(where: { $0.pinID == pinID }), pin.tabID != 0
    {
      showBead(of: pin, fromKeyboard: true)
    } else if model.pinBead?.isFromKeyboard == true {
      hideBead()
    }
  }

  private func press(_ part: PinPart, of pin: FiberPinState) {
    switch part {
    case .icon:
      openPin(pin.pinID)
    case .bead:
      guard let bead = model.pinBead, bead.pinID == pin.pinID else {
        return
      }
      switch bead.action {
      case .reset:
        resettingPinID = pin.pinID
        showBead(of: pin, fromKeyboard: bead.isFromKeyboard)
        onResetPin(pin.pinID)
      case .close:
        onClose(pin.tabID)
      }
    case .bridge:
      break
    }
  }

  // MARK: Scrolling

  /// Scrolls the list, when it's longer than the panel. Fingers can stretch
  /// it a little past either end, and it springs back when they lift; a
  /// flick coasts, and stops at the end. The page under it doesn't scroll.
  override func scrollWheel(with event: NSEvent) {
    let range = model.scrollRange
    guard range.upperBound > 0,
      !downloadsBubble.glassFrame.contains(location(of: event))
    else {
      return
    }
    let delta = -event.scrollingDeltaY
    if !event.hasPreciseScrollingDeltas {
      // A notched wheel scrolls a tab a line.
      setScrollOffset(
        clamp(model.scrollOffset + delta * TabListLayout.rowStep, to: range),
        animation: .spring(duration: 0.25, bounce: 0))
    } else if !event.momentumPhase.isEmpty {
      setScrollOffset(clamp(model.scrollOffset + delta, to: range))
    } else {
      switch event.phase {
      case .began, .changed:
        if event.phase == .began {
          dragOffset = model.scrollOffset
        }
        dragOffset += delta
        model.scrollOffset = TabListLayout.rubberBand(dragOffset, in: range)
      case .ended, .cancelled:
        setScrollOffset(
          clamp(model.scrollOffset, to: range),
          animation: .spring(duration: 0.35, bounce: 0))
      case []:
        // A precise device without phases.
        setScrollOffset(clamp(model.scrollOffset + delta, to: range))
      default:
        break
      }
    }
    retargetDrag()
    hover(at: location(of: event))
  }

  private func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>)
    -> CGFloat
  {
    min(max(value, range.lowerBound), range.upperBound)
  }
}

extension TabOverlay: NSMenuItemValidation {
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    item.action == #selector(undo(_:)) ? pendingShelfRemoval != nil : true
  }
}

/// What the tab overlay keeps in place as what it shows changes, until it
/// closes or the window resizes.
private enum PanelHold {
  /// The panel's top, as it opened, while it fits: closing a tab brings the
  /// next under the pointer rather than recentering the panel.
  case top(CGFloat)
  /// The shelf bar's top, once the user has switched shelves: the list grows
  /// and shrinks above it, scrolling past what fits rather than pushing the
  /// bar down.
  case bar(CGFloat)

  var top: CGFloat? {
    if case .top(let top) = self {
      return top
    }
    return nil
  }

  var barTop: CGFloat? {
    if case .bar(let top) = self {
      return top
    }
    return nil
  }
}

/// What Return and Command-W act on in the tab overlay.
enum TabOverlaySelection: Equatable {
  case pin(String)
  case row(TabListRow.ID)
  /// The split's right tab, in its spot.
  case split

  var isPin: Bool {
    if case .pin = self {
      return true
    }
    return false
  }
}

@MainActor
@Observable
final class TabOverlayModel {
  /// The hints under the list, and the rim below them.
  static let footerHeight = PaletteView.footerHeight + PaletteView.rimWidth

  /// The rows the list shows: Home's tabs (those that aren't pins' or shelf
  /// pages'), or a shelf's pages.
  var rows: [TabListRow] = []
  var pins: [FiberPinState] = []
  var activeTabID = 0
  /// The active tab's row, if the list has it.
  var activeRowID: TabListRow.ID?
  /// The shelf whose pages the list shows, or nil for Home.
  var listedShelfName: String?
  /// The shelf bar's capsule and the button after it (see ShelfBar). Empty
  /// in a window without shelves.
  var shelfBarFrame: CGRect = .zero
  var shelfButtonFrame: CGRect = .zero
  var tabDrag: TabDrag?
  /// The window's split, and its right tab, which its spot shows.
  var split: SplitPair?
  var splitTab: FiberTabState?
  var splitSpotFrame: CGRect = .zero
  /// What the pins and the panel come and go with (see TabOverlayMotion).
  var isOpen = false
  var selection: TabOverlaySelection?
  /// Whether the tabs show their numbers, while Option is held.
  var showsNumbers = false
  var pinDrag: PinDrag?
  var pinBead: PinBead?
  /// The part of the pin with its bead out that the pointer is on.
  var focusedPinPart: PinPart?
  var pinBursts: [PinBurst] = []
  /// How many pins the list is below (see TabOverlay.panelPins).
  var panelPinCount = 0
  var closeButton: TabCloseButton?
  /// How far the list is scrolled up the panel.
  var scrollOffset: CGFloat = 0
  /// In the overlay, as tall as fits.
  var panelFrame: CGRect = .zero
  /// The address's and extensions' capsules, and whether they're beside the
  /// panel rather than above it and its pins.
  var bubbleFrames: [CGRect] = []
  var areBubblesBeside = true
  /// The downloads' glass under the panel (see DownloadsBubble): the
  /// capsule, or the list it opens into. Empty with no downloads.
  var downloadsFrame: CGRect = .zero
  var downloadsCornerRadius: CGFloat = 0
  /// The page's, in CIE L* (see TabOverlay.setPageLightness(_:)).
  var pageLightness: Double = 100
  @ObservationIgnored var onSelect: (TabListRow.ID) -> Void = { _ in }
  @ObservationIgnored var onClose: (TabListRow.ID) -> Void = { _ in }
  /// For a pin's tab.
  @ObservationIgnored var onCloseTab: (Int) -> Void = { _ in }
  @ObservationIgnored var onOpenPin: (String) -> Void = { _ in }
  @ObservationIgnored var onUnpin: (String) -> Void = { _ in }
  @ObservationIgnored var onResetPin: (String) -> Void = { _ in }
  @ObservationIgnored var onOpenSplit: () -> Void = {}

  var gridWidth: CGFloat { panelFrame.width }

  /// Whether the split shows, its left or right tab being active.
  var isSplitShown: Bool { split?.contains(activeTabID) ?? false }

  /// The rows as the list shows them: one dragged within it where it would
  /// drop.
  var shownRows: [TabListRow] {
    guard let tabDrag, case .list(let index) = tabDrag.target,
      let from = rows.firstIndex(where: { $0.id == tabDrag.rowID })
    else {
      return rows
    }
    var shown = rows
    let row = shown.remove(at: from)
    shown.insert(row, at: min(index, shown.count))
    return shown
  }

  /// The top of the row dragged within the list, from the list's.
  var liftedRowTop: CGFloat? {
    guard let tabDrag, case .list = tabDrag.target else {
      return nil
    }
    return liftedRowTop(at: tabDrag.point, grabOffset: tabDrag.grabOffset)
  }

  /// How far down the list's rows `point` is, where it's scrolled to now.
  func listContentY(at point: CGPoint) -> CGFloat {
    point.y - panelFrame.minY - listRect.minY + scrollOffset
  }

  /// Where a row's top is with the pointer at `point`, `grabOffset` below it,
  /// kept to the list's rows.
  func liftedRowTop(at point: CGPoint, grabOffset: CGFloat) -> CGFloat {
    let first = TabListLayout.contentInset
    let last = first + CGFloat(max(rows.count - 1, 0)) * TabListLayout.rowStep
    return min(max(listContentY(at: point) - grabOffset, first), last)
  }

  /// The place among the other rows a row lifted to `top` would drop in.
  func dropIndex(forLiftedTop top: CGFloat) -> Int {
    let index = Int(
      ((top - TabListLayout.contentInset) / TabListLayout.rowStep).rounded())
    return min(max(index, 0), max(rows.count - 1, 0))
  }

  /// How many rows aren't wholly in sight below the list's bottom edge.
  var rowsBelow: Int {
    let bottom = scrollOffset + listRect.height
    return rows.indices.filter {
      TabListLayout.contentInset + CGFloat($0) * TabListLayout.rowStep
        + TabListLayout.rowHeight > bottom + 0.5
    }.count
  }

  /// The bottom-left corner of the pins' grid, just above the panel.
  var pinsOrigin: CGPoint {
    CGPoint(x: panelFrame.minX, y: panelFrame.minY - PinGridLayout.spacing)
  }

  var selectedRowID: TabListRow.ID? {
    if case .row(let rowID)? = selection {
      return rowID
    }
    return nil
  }

  /// The pins in the order they show: a dragged one where it would drop.
  var shownPins: [FiberPinState] {
    guard let pinDrag,
      let from = pins.firstIndex(where: { $0.pinID == pinDrag.pinID })
    else {
      return pins
    }
    var shown = pins
    let pin = shown.remove(at: from)
    shown.insert(pin, at: min(pinDrag.targetIndex, shown.count))
    return shown
  }

  var beadIndex: Int? {
    pinBead.flatMap { bead in pins.firstIndex { $0.pinID == bead.pinID } }
  }

  /// How long after the overlay starts to open the address or extensions at
  /// `frame` start to move: beside the panel, by how near they come to its
  /// top-left corner, or above it, with the pins.
  func motionDelay(ofBubble frame: CGRect) -> TimeInterval {
    areBubblesBeside
      ? TabOverlayMotion.delay(at: distanceFromCorner(of: frame))
      : motionDelay(amongPins: frame)
  }

  /// The same for something under the panel, as the panel's wave reaches it.
  func motionDelay(belowPanel frame: CGRect) -> TimeInterval {
    frame.isEmpty
      ? 0 : TabOverlayMotion.panelDelay(at: distanceFromCorner(of: frame))
  }

  /// The same for something among or above the pins, by where it comes
  /// between the nearest pin and the farthest, or with the panel's wave if
  /// there are none.
  func motionDelay(amongPins frame: CGRect) -> TimeInterval {
    guard let (nearest, farthest) = pinDistances else {
      return TabOverlayMotion.panelDelay(at: distanceFromCorner(of: frame))
    }
    let fraction =
      farthest > nearest
      ? (distanceFromCorner(of: frame) - nearest) / (farthest - nearest) : 0
    return min(max(fraction, 0), 1)
      * TabOverlayMotion.pinsDuration(reach: farthest - nearest)
  }

  /// How long opening takes, which closing plays back.
  var motionSpan: TimeInterval {
    let pinsDelay =
      pinDistances.map {
        TabOverlayMotion.pinsDuration(reach: $0.farthest - $0.nearest)
      } ?? 0
    let bubblesDelay = max(
      bubbleFrames.map(motionDelay(ofBubble:)).max() ?? 0,
      motionDelay(belowPanel: downloadsFrame),
      motionDelay(belowPanel: shelfButtonFrame),
      motionDelay(belowPanel: splitSpotFrame))
    return TabOverlayMotion.span(
      lastDelay: max(pinsDelay, bubblesDelay),
      panelReach: PanelWave.reach(of: panelFrame.size))
  }

  /// How far the nearest pin and the farthest are from the panel's corner.
  private var pinDistances: (nearest: CGFloat, farthest: CGFloat)? {
    guard !pins.isEmpty else {
      return nil
    }
    // The further across and up a pin is, the farther it is, so the farthest
    // is the last, or the last of the row below it.
    let columns = PinGridLayout.columns(width: gridWidth)
    let topRowStart = (pins.count - 1) / columns * columns
    let nearest = distanceFromCorner(of: pinFrame(0))
    let farthest = [pins.count - 1, topRowStart - 1].filter { $0 >= 0 }
      .map { distanceFromCorner(of: pinFrame($0)) }.max() ?? nearest
    return (nearest, farthest)
  }

  func motionDelay(ofPin index: Int) -> TimeInterval {
    motionDelay(amongPins: pinFrame(index))
  }

  /// The glass, for the black pooled under it: the panel, each row of pins,
  /// the split's spot, the address's and extensions' capsules, and the
  /// downloads'.
  var poolShapes: [DimmingPool.Shape] {
    var shapes = [
      DimmingPool.Shape(
        id: "panel", frame: panelFrame, cornerRadius: PaletteView.cornerRadius)
    ]
    let columns = PinGridLayout.columns(width: gridWidth)
    for start in stride(from: 0, to: pins.count, by: columns) {
      let count = min(pins.count - start, columns)
      var row = pinFrame(start)
      row.size.width = pinFrame(start + count - 1).maxX - row.minX
      shapes.append(
        DimmingPool.Shape(
          id: "pins\(start / columns)", frame: row,
          cornerRadius: PinGridLayout.diameter / 2))
    }
    shapes.append(
      DimmingPool.Shape(
        id: "splitSpot", frame: splitSpotFrame,
        cornerRadius: splitSpotFrame.height / 2))
    for (index, frame) in bubbleFrames.enumerated() {
      shapes.append(
        DimmingPool.Shape(
          id: "bubble\(index)", frame: frame, cornerRadius: frame.height / 2))
    }
    shapes.append(
      DimmingPool.Shape(
        id: "downloads", frame: downloadsFrame,
        cornerRadius: downloadsCornerRadius))
    for (id, frame) in [
      ("shelves", shelfBarFrame), ("shelfButton", shelfButtonFrame),
    ] {
      shapes.append(
        DimmingPool.Shape(id: id, frame: frame, cornerRadius: frame.height / 2))
    }
    return shapes.filter { !$0.frame.isEmpty }
  }

  /// The circle of the pin at `index`.
  private func pinFrame(_ index: Int) -> CGRect {
    let origin = PinGridLayout.origin(of: index, width: gridWidth)
    return CGRect(
      x: pinsOrigin.x + origin.x, y: pinsOrigin.y + origin.y,
      width: PinGridLayout.diameter, height: PinGridLayout.diameter)
  }

  private func distanceFromCorner(of frame: CGRect) -> CGFloat {
    let corner = panelFrame.origin
    return hypot(
      max(frame.minX - corner.x, corner.x - frame.maxX, 0),
      max(frame.minY - corner.y, corner.y - frame.maxY, 0))
  }

  /// The pins' rows over a panel `width` wide, and the space under them.
  func pinsHeight(width: CGFloat) -> CGFloat {
    guard panelPinCount > 0 else {
      return 0
    }
    return PinGridLayout.height(count: panelPinCount, width: width)
      + PinGridLayout.spacing
  }

  /// With no tabs, the top rim's, so the hints sit as far from the panel's top
  /// as from its bottom; an empty shelf's, a row for what to do with it.
  var listContentHeight: CGFloat {
    rows.isEmpty && listedShelfName == nil
      ? PaletteView.rimWidth : TabListLayout.panelHeight(rows: rows.count)
  }

  /// From the panel's top-left corner.
  var listRect: CGRect {
    CGRect(
      x: 0, y: 0, width: panelFrame.width,
      height: max(panelFrame.height - Self.footerHeight, 0))
  }

  var scrollRange: ClosedRange<CGFloat> {
    0...max(listContentHeight - listRect.height, 0)
  }
}

/// Draws the tab overlay's panel and pins; TabOverlay handles all input. The
/// highlight glides to the selected tab.
struct TabOverlayView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The black pooled under the glass (see DimmingPool).
  private static let poolSpread: CGFloat = 80
  private static let poolRadius: CGFloat = 80
  private static let poolDimming = Dimming(light: 0.6, dark: 0.75)

  let model: TabOverlayModel

  var body: some View {
    let panel = model.panelFrame
    let list = model.listRect
    let rim = PaletteView.rimWidth
    let pins = model.pinsOrigin
    ZStack(alignment: .topLeading) {
      DimmingPool(
        shapes: model.poolShapes, spread: Self.poolSpread,
        radius: Self.poolRadius,
        opacity: Self.poolDimming.opacity(
          forPageLightness: model.pageLightness))
      ZStack(alignment: .topLeading) {
        PanelShadow(cornerRadius: PaletteView.cornerRadius)
        RimmedGlass(cornerRadius: PaletteView.cornerRadius, rimWidth: rim)
          .accessibilityHidden(true)

        TabList(
          width: panel.width, showsURL: true,
          showsNumbers: model.showsNumbers, rows: model.shownRows,
          activeRowID: model.activeRowID,
          highlightedRowID: model.tabDrag == nil ? model.selectedRowID : nil,
          closeButton: model.closeButton, draggedRowID: model.tabDrag?.rowID,
          liftedRowTop: model.liftedRowTop,
          onSelect: model.onSelect, onClose: model.onClose
        )
        .fixedSize(horizontal: false, vertical: true)
        .offset(y: -model.scrollOffset)
        .frame(width: panel.width, height: list.height, alignment: .top)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.listedShelfName ?? "Tabs")

        // A list that goes on past the panel says how much further.
        if model.rowsBelow > 0 {
          MoreBelow(count: model.rowsBelow)
            .frame(height: PaletteView.footerHeight)
            .offset(
              x: rim + PaletteView.horizontalInset,
              y: panel.height - TabOverlayModel.footerHeight)
            .transition(.opacity)
        }

        if let name = model.listedShelfName, model.rows.isEmpty {
          Text("Drag tabs onto “\(name)” to keep them here")
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .frame(width: panel.width, height: list.height)
            .transition(.opacity)
        }

        HintsView(
          kind: model.listedShelfName == nil
            ? .home : model.rows.isEmpty ? .emptyShelf : .shelf)
          .frame(
            width: max(
              panel.width - 2 * (rim + PaletteView.horizontalInset), 0),
            height: PaletteView.footerHeight, alignment: .trailing
          )
          .offset(
            x: rim + PaletteView.horizontalInset,
            y: panel.height - TabOverlayModel.footerHeight)
      }
      .frame(width: panel.width, height: panel.height, alignment: .topLeading)
      .mask {
        PanelWave(progress: model.isOpen ? 1 : 0, size: panel.size)
          .animation(
            TabOverlayMotion.panelAnimation(
              reach: PanelWave.reach(of: panel.size), span: model.motionSpan,
              isOpening: model.isOpen),
            value: model.isOpen)
          .padding(-PanelWave.outset)
      }
      .offset(x: panel.minX, y: panel.minY)

      PinGrid(model: model)
        .frame(width: panel.width, height: max(pins.y, 0))
        .offset(x: pins.x)
        // Read before the tabs, as they show.
        .accessibilitySortPriority(1)

      splitSpot

    }
    // Tabs opening and closing grow and shrink the panel, and rows of pins
    // coming and going can move it.
    .animation(
      .spring(duration: 0.3, bounce: 0).slowMotion,
      value: model.rows.map(\.id))
    .animation(
      .spring(duration: 0.3, bounce: 0).slowMotion, value: model.panelPinCount)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain)
  }

  /// Comes from the right, beside the panel, as the wave reaches it.
  private var splitSpot: some View {
    let frame = model.splitSpotFrame
    let delay = model.motionDelay(belowPanel: frame)
    let span = model.motionSpan
    let tab = model.splitTab
    return SplitSpot(
      tab: tab, isActive: tab.map { $0.tabID == model.activeTabID } ?? false,
      isShown: model.isSplitShown, isSelected: model.selection == .split,
      isDropTarget: model.tabDrag?.target == .split
        || model.pinDrag?.isOverSplit == true
    )
    .offset(x: model.isOpen || reduceMotion ? 0 : TabOverlayMotion.sideTravel)
    .animation(
      TabOverlayMotion.animation(
        .offset, delay: delay, span: span, isOpening: model.isOpen),
      value: model.isOpen)
    .opacity(model.isOpen || reduceMotion ? 1 : 0)
    .animation(
      TabOverlayMotion.animation(
        .opacity, delay: delay, span: span, isOpening: model.isOpen),
      value: model.isOpen)
    .offset(x: frame.minX, y: frame.minY)
    .accessibilityElement()
    .accessibilityLabel(
      tab.map { "Right of split: \($0.title.isEmpty ? $0.url : $0.title)" }
        ?? "Right of split")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { model.onOpenSplit() }
  }
}

/// The tab overlay panel's mask as the wave (see TabOverlayMotion) spreads
/// across it from its top-left corner: opaque behind the wave's soft edge, and
/// dimmer past its front. It's `outset` larger than the panel all round.
private struct PanelWave: View, Animatable {
  /// As far as the panel's shadow reaches past it.
  static let outset: CGFloat = 60

  /// From the wave not yet started to past the far corner.
  var progress: CGFloat
  /// The panel's.
  let size: CGSize

  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  /// How far the far corner, shadow and all, is from the panel's.
  static func reach(of size: CGSize) -> CGFloat {
    hypot(size.width + outset, size.height + outset)
  }

  var body: some View {
    let edge = TabOverlayMotion.panelEdgeWidth
    let front = progress * (Self.reach(of: size) + edge)
    RadialGradient(
      colors: [.black, .black.opacity(TabOverlayMotion.panelFloorOpacity)],
      center: UnitPoint(
        x: Self.outset / (size.width + 2 * Self.outset),
        y: Self.outset / (size.height + 2 * Self.outset)),
      startRadius: max(front - edge, 0), endRadius: max(front, 1))
  }
}

/// A row dragged off the list, over everything in the overlay.
private struct TabDragView: View {
  let model: TabOverlayModel

  var body: some View {
    ZStack(alignment: .topLeading) {
      if let drag = model.tabDrag, model.liftedRowTop == nil,
        let row = model.rows.first(where: { $0.id == drag.rowID })
      {
        let isOverTarget = drag.target != nil
        DraggedRow(row: row, isOverTarget: isOverTarget)
          .position(
            DraggedRow.center(for: drag.point, isOverTarget: isOverTarget))
          .animation(
            .spring(duration: 0.3, bounce: 0.25).slowMotion,
            value: isOverTarget)
          .transition(.scale(scale: 0.9).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .animation(
      .spring(duration: 0.25, bounce: 0.2).slowMotion,
      value: model.tabDrag == nil || model.liftedRowTop != nil)
  }
}

/// Lets the pointer through to what's under the dragged row.
private final class TabDragHostingView: NSHostingView<TabDragView> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

/// How many rows are past the list's bottom edge, at the footer's left, in
/// the hints' style.
private struct MoreBelow: View {
  let count: Int

  var body: some View {
    HStack(spacing: PaletteView.hintInnerSpacing) {
      Text("\(count) more")
        .foregroundStyle(.secondary)
        .contentTransition(.numericText(value: Double(count)))
      Image(systemName: "chevron.down")
        .fontWeight(.medium)
        .foregroundStyle(.tertiary)
    }
    .font(.system(size: 11))
    .animation(.easeInOut(duration: 0.2).slowMotion, value: count)
  }
}

/// The keys, like the command palette's.
private struct HintsView: View {
  private static let hints = [
    ("Switch to Tab", "↩"), ("Close Tab", "⌘W"), ("Close", "esc"),
  ]
  private static let shelfHints = [
    ("Open", "↩"), ("Close Tab", "⌘W"), ("Remove", "⌫"), ("Close", "esc"),
  ]

  enum Kind {
    case home, shelf, emptyShelf
  }

  let kind: Kind

  private var hints: [(String, String)] {
    switch kind {
    case .home: Self.hints
    case .shelf: Self.shelfHints
    case .emptyShelf: [("Close", "esc")]
    }
  }

  var body: some View {
    HStack(spacing: PaletteView.hintSpacing) {
      ForEach(hints, id: \.0) { action, key in
        HStack(spacing: PaletteView.hintInnerSpacing) {
          Text(action)
            .foregroundStyle(.secondary)
          Text(key)
            .fontWeight(.medium)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .font(.system(size: 11))
  }
}
