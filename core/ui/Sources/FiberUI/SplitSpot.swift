import AppKit
import FiberBridge
import SwiftUI

/// The window's split's tabs (see FiberSplit).
struct SplitPair: Equatable {
  let leftTabID: Int
  let rightTabID: Int

  func contains(_ tabID: Int) -> Bool {
    tabID == leftTabID || tabID == rightTabID
  }

  /// The tab that `tabID`, or a new tab for nil (a pin's copy), would go on
  /// the right of: the split's other tab, or without one, the active tab, or
  /// else the one of `tabs` used last.
  static func leftTab(
    beside tabID: Int?, in split: SplitPair?, tabs: [FiberTabState],
    activeTabID: Int
  ) -> Int? {
    if let split {
      return tabID == split.leftTabID ? split.rightTabID : split.leftTabID
    }
    let others = tabs.filter { $0.tabID != tabID }
    if others.contains(where: { $0.tabID == activeTabID }) {
      return activeTabID
    }
    return others.max { $0.lastActiveTime < $1.lastActiveTime }?.tabID
  }
}

/// Where a split's right tab goes in the tab overlay: a circle of glass like
/// a pin's, to the right of the panel or at the end of the row under it, that
/// a row dropped on shows on the right of the page. As tall as the capsules
/// around the panel, like the shelf bar's button.
enum SplitSpotLayout {
  static let diameter = GlassCapsule.height
  /// How far around the circle a dragged row still drops on it.
  static let dropSlop: CGFloat = 16

  static func contains(_ point: CGPoint, frame: CGRect) -> Bool {
    hypot(point.x - frame.midX, point.y - frame.midY) <= diameter / 2
  }

  static func takesDrop(at point: CGPoint, frame: CGRect) -> Bool {
    hypot(point.x - frame.midX, point.y - frame.midY)
      <= diameter / 2 + dropSlop
  }
}

/// The split's spot: the split glyph while it's empty, and the right tab's
/// icon once it has one, ringed while that tab is active, and dimmed while
/// the split doesn't show. A row dragged over it swells it.
struct SplitSpot: View {
  /// The right tab, if there's a split.
  let tab: FiberTabState?
  let isActive: Bool
  /// Whether the split shows, its left or right tab being active.
  let isShown: Bool
  let isSelected: Bool
  let isDropTarget: Bool

  var body: some View {
    let rim = GlassCapsule.rimWidth
    let diameter = SplitSpotLayout.diameter
    let inner = Circle().inset(by: rim)
    ZStack {
      RimmedGlass(cornerRadius: diameter / 2, rimWidth: rim)
      inner
        .fill(Color.primary.opacity(0.22))
        .opacity(isSelected || isDropTarget ? 1 : 0)
      inner
        .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
        .opacity(isActive || isDropTarget ? 1 : 0)
      icon
        .frame(width: 16, height: 16)
        .opacity(tab == nil || isShown ? 1 : 0.5)
        .contentTransition(.opacity)
    }
    .frame(width: diameter, height: diameter)
    .scaleEffect(isDropTarget ? 1.18 : 1)
    .animation(
      .spring(duration: 0.3, bounce: 0.35).slowMotion, value: isDropTarget)
    .animation(.easeInOut(duration: 0.15).slowMotion, value: isSelected)
    .animation(.easeInOut(duration: 0.15).slowMotion, value: isActive)
    .animation(
      .spring(duration: 0.35, bounce: 0.3).slowMotion, value: tab?.tabID)
  }

  @ViewBuilder private var icon: some View {
    if let tab {
      if tab.isLoading {
        ProgressView()
          .controlSize(.small)
          .scaleEffect(0.75)
      } else if let favicon = tab.favicon {
        Image(nsImage: favicon)
          .renderingMode(favicon.isTemplate ? .template : .original)
          .resizable()
          .interpolation(.high)
      } else {
        Image(systemName: "globe")
          .foregroundStyle(.secondary)
      }
    } else {
      Image(systemName: "rectangle.split.2x1")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isDropTarget ? .primary : .tertiary)
    }
  }
}
