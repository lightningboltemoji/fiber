import AppKit

/// The window's toolbar, shown with Command-S: a row of glass capsules along
/// the top of the page, level with the traffic lights' capsule. The address
/// capsule holds the navigation buttons and the page's address, which opens
/// the command palette when clicked; the capsule at the end holds the
/// extensions (see ExtensionsBar), and a placeholder for menus.
///
/// The window controller wires up the controls, places the row, and shows and
/// hides it.
@MainActor
final class Toolbar: NSView {
  /// The capsules' height, which matches the traffic lights' capsule.
  static let height: CGFloat = 40
  static let spacing: CGFloat = 8
  private static let rimWidth: CGFloat = 5
  static let buttonSize: CGFloat = 28
  /// Between the end capsule's content and its rim.
  private static let endPadding: CGFloat = 6

  let backButton = Toolbar.makeButton(symbol: "chevron.backward", label: "Back")
  let forwardButton = Toolbar.makeButton(
    symbol: "chevron.forward", label: "Forward")
  let reloadButton = Toolbar.makeButton(
    symbol: "arrow.clockwise", label: "Reload")
  /// Shows the page's address; the window controller opens the command
  /// palette from it.
  let addressButton = Toolbar.makeAddressButton()
  /// The extensions menu's button and the extensions pinned beside it.
  let extensionsBar = ExtensionsBar()

  private let addressCapsule = RimmedGlassView(rimWidth: Toolbar.rimWidth)
  private let extensionsCapsule = RimmedGlassView(rimWidth: Toolbar.rimWidth)
  private let endContent = NSStackView()

  override init(frame: NSRect) {
    super.init(frame: frame)
    for capsule in [addressCapsule, extensionsCapsule] {
      capsule.cornerRadius = Self.height / 2
      addSubview(capsule)
    }
    addressCapsule.contentView = makeAddressContent()
    extensionsCapsule.contentView = makeExtensionsContent()
    // Pinning an extension widens the capsule, and the address gives way.
    extensionsBar.onResize = { [weak self] in self?.layoutCapsules() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // Clicks between the capsules go to the page.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let view = super.hitTest(point)
    return view === self ? nil : view
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    layoutCapsules()
  }

  /// The end capsule fits its content; the address capsule takes the rest.
  private func layoutCapsules() {
    let extensionsWidth =
      endContent.fittingSize.width + 2 * (Self.rimWidth + Self.endPadding)
    let extensionsX = bounds.width - extensionsWidth
    extensionsCapsule.frame = NSRect(
      x: extensionsX, y: 0, width: extensionsWidth, height: Self.height)
    addressCapsule.frame = NSRect(
      x: 0, y: 0, width: max(extensionsX - Self.spacing, 0),
      height: Self.height)
  }

  /// Where the extensions menu's button is, in `view`'s coordinates, even
  /// while the toolbar is hidden: where popups come from.
  func extensionsMenuButtonRect(in view: NSView) -> NSRect {
    layoutSubtreeIfNeeded()
    let button = extensionsBar.menuButton
    return button.convert(button.bounds, to: view)
  }

  /// Shows the page's short address (usually just its host), or a prompt when
  /// there's none, as on the New Tab page.
  func setAddress(_ address: String) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingMiddle
    addressButton.attributedTitle = NSAttributedString(
      string: address.isEmpty ? "Search or enter address" : address,
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: address.isEmpty
          ? NSColor.tertiaryLabelColor : NSColor.labelColor,
        .paragraphStyle: paragraph,
      ])
  }

  /// Turns Reload into Stop while the page loads.
  func setLoading(_ loading: Bool) {
    let label = loading ? "Stop" : "Reload"
    reloadButton.image = NSImage(
      systemSymbolName: loading ? "xmark" : "arrow.clockwise",
      accessibilityDescription: label)
    reloadButton.toolTip = label
  }

  /// Back and Forward at the start, the address in the middle, and Reload at
  /// the end. Dragging the space between them moves the window.
  private func makeAddressContent() -> NSView {
    let content = WindowDragArea()
    let navigation = NSStackView(views: [backButton, forwardButton])
    navigation.spacing = 0
    // The address takes the rest of the width.
    navigation.setHuggingPriority(.required, for: .horizontal)
    for view in [navigation, addressButton, reloadButton] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    NSLayoutConstraint.activate([
      navigation.leadingAnchor.constraint(
        equalTo: content.leadingAnchor, constant: 2),
      navigation.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      reloadButton.trailingAnchor.constraint(
        equalTo: content.trailingAnchor, constant: -2),
      reloadButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      addressButton.leadingAnchor.constraint(
        equalTo: navigation.trailingAnchor, constant: 2),
      addressButton.trailingAnchor.constraint(
        equalTo: reloadButton.leadingAnchor, constant: -2),
      addressButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      addressButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
    ])
    return content
  }

  /// The extensions, then a stand-in for the menu button to come, which does
  /// nothing.
  private func makeExtensionsContent() -> NSView {
    let content = WindowDragArea()
    let more = NSImageView(
      image: NSImage(
        systemSymbolName: "ellipsis", accessibilityDescription: "More")!)
    more.contentTintColor = .tertiaryLabelColor
    more.widthAnchor.constraint(equalToConstant: Self.buttonSize).isActive =
      true
    endContent.setViews([extensionsBar, more], in: .leading)
    endContent.spacing = 2
    endContent.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(endContent)
    NSLayoutConstraint.activate([
      endContent.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      endContent.centerYAnchor.constraint(equalTo: content.centerYAnchor),
    ])
    return content
  }

  private static func makeAddressButton() -> NSButton {
    let button = NSButton(title: "", target: nil, action: nil)
    button.bezelStyle = .accessoryBarAction
    button.showsBorderOnlyWhileMouseInside = true
    button.toolTip = "Search or enter address"
    button.setContentCompressionResistancePriority(
      .defaultLow, for: .horizontal)
    return button
  }

  static func makeButton(symbol: String, label: String) -> ToolbarButton {
    let button = ToolbarButton()
    button.image = NSImage(
      systemSymbolName: symbol, accessibilityDescription: label)
    button.imagePosition = .imageOnly
    button.bezelStyle = .accessoryBarAction
    button.showsBorderOnlyWhileMouseInside = true
    button.toolTip = label
    button.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
    button.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
    return button
  }
}
