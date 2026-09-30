import AppKit

/// The window's toolbar, shown with Command-S: glass capsules along the top
/// of the page, level with the traffic lights'. Buttons are circles and the
/// address a capsule, so the buttons at each end of a capsule meet its rim.
@MainActor
final class Toolbar: NSView {
  /// The capsules' height, which matches the traffic lights' capsule.
  static let height: CGFloat = 40
  static let spacing: CGFloat = 8
  private static let rimWidth: CGFloat = 5
  static let buttonSize: CGFloat = 28
  /// Between the buttons at each end of a capsule and its rim.
  private static let endInset: CGFloat = 2

  let backButton = Toolbar.makeButton(symbol: "chevron.backward", label: "Back")
  let forwardButton = Toolbar.makeButton(
    symbol: "chevron.forward", label: "Forward")
  let reloadButton = Toolbar.makeButton(
    symbol: "arrow.clockwise", label: "Reload")
  /// Shows the page's address; the window controller opens the command
  /// palette from it.
  let addressButton = Toolbar.makeAddressButton()
  let extensionsBar = ExtensionsBar()

  private let addressCapsule = RimmedGlassView(rimWidth: Toolbar.rimWidth)
  private let extensionsCapsule = RimmedGlassView(rimWidth: Toolbar.rimWidth)
  private let endContent = NSStackView()
  private let isIncognito: Bool

  init(isIncognito: Bool) {
    self.isIncognito = isIncognito
    super.init(frame: .zero)
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
      endContent.fittingSize.width + 2 * (Self.rimWidth + Self.endInset)
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
  }

  /// Turns Reload into Stop while the page loads.
  func setLoading(_ loading: Bool) {
    let label = loading ? "Stop" : "Reload"
    reloadButton.image = NSImage(
      systemSymbolName: loading ? "xmark" : "arrow.clockwise",
      accessibilityDescription: label)
    reloadButton.toolTip = label
  }

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
        equalTo: content.leadingAnchor, constant: Self.endInset),
      navigation.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      reloadButton.trailingAnchor.constraint(
        equalTo: content.trailingAnchor, constant: -Self.endInset),
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

  /// The ellipsis after the extensions is an inert stand-in for a menu button.
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
    button.borderShape = .capsule
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
    button.borderShape = .circle
    button.showsBorderOnlyWhileMouseInside = true
    button.toolTip = label
    button.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
    button.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
    return button
  }
}
