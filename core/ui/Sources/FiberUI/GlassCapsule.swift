import AppKit

/// The glass capsules the window's controls float in (the find bar, the tab
/// overlay's address and extensions), as tall as the traffic lights' capsule.
/// Buttons are circles, so those at each end of a capsule meet its rim.
enum GlassCapsule {
  static let height: CGFloat = 40
  static let spacing: CGFloat = 8
  static let rimWidth: CGFloat = 5
  static let buttonSize: CGFloat = 28
  /// Between the buttons at each end of a capsule and its rim.
  static let endInset: CGFloat = 2

  @MainActor
  static func makeButton(symbol: String, label: String) -> CapsuleButton {
    let button = CapsuleButton()
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
