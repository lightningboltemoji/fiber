import AppKit
import FiberBridge

@objc @implementation extension FiberContextMenuItem {
  let kind: FiberContextMenuItemKind
  let itemID: Int
  let title: String
  let symbolName: String?
  let enabled: Bool
  let checked: Bool
  let submenu: [FiberContextMenuItem]

  init(
    kind: FiberContextMenuItemKind, itemID: Int, title: String,
    symbolName: String?, enabled: Bool, checked: Bool,
    submenu: [FiberContextMenuItem]
  ) {
    self.kind = kind
    self.itemID = itemID
    self.title = title
    self.symbolName = symbolName
    self.enabled = enabled
    self.checked = checked
    self.submenu = submenu
    super.init()
  }
}

@objc @implementation extension FiberContextMenuFactory {
  @objc(menuWithItems:actions:)
  class func menu(
    with items: [FiberContextMenuItem],
    actions: any FiberContextMenuActions
  ) -> any FiberContextMenu {
    ContextMenu(items: items, actions: actions)
  }
}

/// A page's context menu: a native menu, popped up where the user clicked.
/// AppKit adds what it adds to any text view's menu (Services, Writing Tools)
/// for the view it pops up in.
@MainActor
final class ContextMenu: NSObject, FiberContextMenu, NSMenuDelegate {
  private let actions: any FiberContextMenuActions
  private let menu = NSMenu()
  private var menuItems: [Int: NSMenuItem] = [:]
  private var isOpen = false

  init(items: [FiberContextMenuItem], actions: any FiberContextMenuActions) {
    self.actions = actions
    super.init()
    fill(menu, with: items)
    menu.delegate = self
  }

  @objc(popUpWithEvent:inView:)
  func popUp(with event: NSEvent, in view: NSView) {
    NSMenu.popUpContextMenu(menu, with: event, for: view)
  }

  @objc(updateItemWithID:title:enabled:hidden:)
  func updateItem(withID itemID: Int, title: String, enabled: Bool, hidden: Bool)
  {
    guard let item = menuItems[itemID] else {
      return
    }
    item.title = title
    item.isEnabled = enabled
    item.isHidden = hidden
  }

  func cancel() {
    menu.cancelTracking()
  }

  // MARK: NSMenuDelegate

  func menuWillOpen(_ menu: NSMenu) {
    isOpen = true
    actions.contextMenuWillOpen()
  }

  func menuDidClose(_ menu: NSMenu) {
    guard isOpen else {
      return
    }
    isOpen = false
    actions.contextMenuDidClose()
  }

  // MARK: Private

  private func fill(_ menu: NSMenu, with items: [FiberContextMenuItem]) {
    // Items are enabled as the browser says, not by AppKit's validation.
    menu.autoenablesItems = false
    for item in items {
      if item.kind == .separator {
        menu.addItem(.separator())
        continue
      }
      let menuItem = NSMenuItem(
        title: item.title, action: nil, keyEquivalent: "")
      menuItem.isEnabled = item.enabled
      menuItem.state = item.checked ? .on : .off
      if let symbolName = item.symbolName {
        menuItem.image = NSImage(
          systemSymbolName: symbolName, accessibilityDescription: nil)
      }
      if item.kind == .submenu {
        let submenu = NSMenu(title: item.title)
        fill(submenu, with: item.submenu)
        menuItem.submenu = submenu
      } else {
        menuItem.tag = item.itemID
        menuItem.target = self
        menuItem.action = #selector(choose(_:))
      }
      menuItems[item.itemID] = menuItem
      menu.addItem(menuItem)
    }
  }

  @objc private func choose(_ sender: NSMenuItem) {
    actions.contextMenuDidSelectItem(withID: sender.tag)
  }
}
