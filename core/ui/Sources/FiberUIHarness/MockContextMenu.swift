import AppKit
import FiberBridge

/// Plays the part of Chrome's context menu for a right-click on a mock page.
@MainActor
final class MockContextMenu: NSObject, FiberContextMenuActions {
  private var titles: [Int: String] = [:]
  private let onSelect: (String) -> Void

  /// Shows the menu for `link` (or the page, if nil) at `event` in `view`, and
  /// returns once it closes.
  static func show(
    for link: String?, event: NSEvent, in view: NSView,
    onSelect: @escaping (String) -> Void
  ) {
    let actions = MockContextMenu(onSelect: onSelect)
    let items =
      link == nil
      ? [
        actions.command("View Page Source", "chevron.left.forwardslash.chevron.right"),
        actions.command("Inspect", "hammer"),
        .separator,
        actions.submenu(
          "Mock Extension",
          [
            actions.command("Highlight Page"),
            actions.command("Read Later", checked: true),
            actions.command("Unavailable Here", enabled: false),
          ]),
      ]
      : [
        actions.command("Open Link in New Tab", "plus.square.on.square"),
        actions.command("Open Link in New Window", "macwindow.badge.plus"),
        actions.command("Open Link in Incognito Window", "hand.raised"),
        .separator,
        actions.command("Save Link As…", "square.and.arrow.down"),
        actions.command("Copy Link Address", "link"),
        .separator,
        actions.command("Inspect", "hammer"),
      ]
    FiberContextMenuFactory.menu(with: items, actions: actions)
      .popUp(with: event, in: view)
  }

  private init(onSelect: @escaping (String) -> Void) {
    self.onSelect = onSelect
  }

  func contextMenuWillOpen() {}

  func contextMenuDidClose() {}

  func contextMenuDidSelectItem(withID itemID: Int) {
    if let title = titles[itemID] {
      onSelect(title)
    }
  }

  private func command(
    _ title: String, _ symbolName: String? = nil, enabled: Bool = true,
    checked: Bool = false
  ) -> FiberContextMenuItem {
    item(.command, title, symbolName, enabled: enabled, checked: checked)
  }

  private func submenu(_ title: String, _ items: [FiberContextMenuItem])
    -> FiberContextMenuItem
  {
    item(.submenu, title, nil, submenu: items)
  }

  private func item(
    _ kind: FiberContextMenuItemKind, _ title: String, _ symbolName: String?,
    enabled: Bool = true, checked: Bool = false,
    submenu: [FiberContextMenuItem] = []
  ) -> FiberContextMenuItem {
    let itemID = titles.count
    titles[itemID] = title
    return FiberContextMenuItem(
      kind: kind, itemID: itemID, title: title, symbolName: symbolName,
      enabled: enabled, checked: checked, submenu: submenu)
  }
}

extension FiberContextMenuItem {
  fileprivate static let separator = FiberContextMenuItem(
    kind: .separator, itemID: -1, title: "", symbolName: nil, enabled: false,
    checked: false, submenu: [])
}
