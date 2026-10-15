import AppKit
import FiberBridge

/// The menus a right-click opens on a pin, a shelf or a shelf's page, or on a
/// tab in the tab overlay or picker.
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

  /// For a shelf's segment in the tab overlay.
  static func menu(
    for shelf: FiberShelfState, rename: @escaping () -> Void,
    delete: @escaping () -> Void
  ) -> NSMenu {
    let menu = NSMenu()
    menu.addItem(ActionMenuItem("Rename…", handler: rename))
    menu.addItem(.separator())
    menu.addItem(ActionMenuItem("Delete “\(shelf.name)”", handler: delete))
    return menu
  }

  /// For a page on `shelf`, one of `shelves`.
  static func menu(
    for page: FiberPinState, on shelf: FiberShelfState,
    shelves: [FiberShelfState], actions: any FiberWindowActions,
    shelvesActions: any FiberShelvesActions
  ) -> NSMenu {
    let menu = NSMenu()
    let id = page.pinID
    if page.tabID != 0 {
      if !page.isAtPinnedURL {
        menu.addItem(
          ActionMenuItem("Back to saved page") {
            actions.resetPin(withID: id)
          })
        menu.addItem(
          ActionMenuItem("Replace with this page") {
            actions.updateURLOfPin(withID: id)
          })
        menu.addItem(.separator())
      }
      let tabID = page.tabID
      menu.addItem(
        ActionMenuItem("Close tab") { actions.closeTab(withID: tabID) })
    }
    let others = [("Home", "")]
      + shelves.filter { $0.shelfID != shelf.shelfID }.map {
        ($0.name, $0.shelfID)
      }
    menu.addItem(
      moveItem(to: others) {
        shelvesActions.moveShelfPage(withID: id, toShelfWithID: $0)
      })
    menu.addItem(.separator())
    menu.addItem(
      ActionMenuItem("Remove from “\(shelf.name)”") {
        shelvesActions.removeShelfPage(withID: id)
      })
    return menu
  }

  /// For a tab that isn't a pin's or a shelf page's. `canPin` is whether the
  /// window has pins, and so shelves.
  static func menu(
    forTabWithID tabID: Int, canPin: Bool, shelves: [FiberShelfState],
    actions: any FiberWindowActions,
    shelvesActions: (any FiberShelvesActions)?
  ) -> NSMenu {
    let menu = NSMenu()
    if canPin {
      menu.addItem(ActionMenuItem("Pin tab") { actions.pinTab(withID: tabID) })
      if let shelvesActions, !shelves.isEmpty {
        menu.addItem(
          moveItem(to: shelves.map { ($0.name, $0.shelfID) }) {
            shelvesActions.moveTab(withID: tabID, toShelfWithID: $0)
          })
      }
      menu.addItem(.separator())
    }
    menu.addItem(
      ActionMenuItem("Close tab") { actions.closeTab(withID: tabID) })
    return menu
  }

  /// "Move to", with a submenu of `places` (their names and IDs).
  private static func moveItem(
    to places: [(name: String, id: String)], move: @escaping (String) -> Void
  ) -> NSMenuItem {
    let item = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    for place in places {
      submenu.addItem(ActionMenuItem(place.name) { move(place.id) })
    }
    item.submenu = submenu
    return item
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
