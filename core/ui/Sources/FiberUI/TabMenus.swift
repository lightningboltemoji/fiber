import AppKit
import FiberBridge

/// The menus a right-click opens on a pin, or on a tab in the tab sidebar or
/// picker.
@MainActor
enum TabMenus {
  static func menu(for pin: FiberPinState, actions: any FiberWindowActions)
    -> NSMenu
  {
    let menu = NSMenu()
    let id = pin.pinID
    if pin.tabID != 0 {
      if !pin.isAtPinnedURL {
        menu.addItem(
          ActionMenuItem("Back to pinned page") {
            actions.resetPin(withID: id)
          })
        menu.addItem(
          ActionMenuItem("Replace with this page") {
            actions.updateURLOfPin(withID: id)
          })
        menu.addItem(.separator())
      }
      let tabID = pin.tabID
      menu.addItem(
        ActionMenuItem("Close tab") { actions.closeTab(withID: tabID) })
    }
    menu.addItem(ActionMenuItem("Unpin") { actions.unpinPin(withID: id) })
    return menu
  }

  /// For a tab that isn't a pin's. `canPin` is whether the window has pins.
  static func menu(
    forTabWithID tabID: Int, canPin: Bool, actions: any FiberWindowActions
  ) -> NSMenu {
    let menu = NSMenu()
    if canPin {
      menu.addItem(ActionMenuItem("Pin tab") { actions.pinTab(withID: tabID) })
      menu.addItem(.separator())
    }
    menu.addItem(
      ActionMenuItem("Close tab") { actions.closeTab(withID: tabID) })
    return menu
  }
}

/// A menu item that runs a closure.
private final class ActionMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(_ title: String, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(run(_:)), keyEquivalent: "")
    target = self
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  @objc private func run(_ sender: Any?) {
    handler()
  }
}
