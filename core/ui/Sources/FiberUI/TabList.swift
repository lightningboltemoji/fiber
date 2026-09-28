import FiberBridge
import SwiftUI

/// The layout of a glass panel listing the tabs, the tab picker's or the tab
/// sidebar's, shared by their hit testing and drawing.
enum TabListLayout {
  static let panelWidth: CGFloat = 264
  static let cornerRadius: CGFloat = 22
  static let rimWidth: CGFloat = 5
  static let rowHeight: CGFloat = 34
  static let rowSpacing: CGFloat = 2
  static var rowStep: CGFloat { rowHeight + rowSpacing }
  /// From the panel's edge to its rows: the glass's rim and a little more.
  static let contentInset: CGFloat = 10
  /// Scrolling past the first or last tab stretches no further than this.
  static let rubberBandLimit: CGFloat = 120

  /// The center of row `row`, from the panel's top.
  static func rowCenter(_ row: Int) -> CGFloat {
    contentInset + CGFloat(row) * rowStep + rowHeight / 2
  }

  static func panelHeight(rows: Int) -> CGFloat {
    2 * contentInset + CGFloat(max(rows, 1)) * rowStep - rowSpacing
  }

  /// `value` clamped to `range`, except that it stretches a little past it
  /// with growing resistance.
  static func rubberBand(_ value: CGFloat, in range: ClosedRange<CGFloat>)
    -> CGFloat
  {
    func stretch(_ distance: CGFloat) -> CGFloat {
      (1 - 1 / (distance * 0.55 / rubberBandLimit + 1)) * rubberBandLimit
    }
    if value < range.lowerBound {
      return range.lowerBound - stretch(range.lowerBound - value)
    }
    if value > range.upperBound {
      return range.upperBound + stretch(value - range.upperBound)
    }
    return value
  }
}

/// A panel's rows, with a highlight that glides to the highlighted tab.
struct TabList: View {
  let tabs: [FiberTabState]
  let activeTabID: Int
  let highlightedTabID: Int?
  /// For accessibility, which presses a tab to select it.
  let onSelect: (Int) -> Void

  var body: some View {
    VStack(spacing: TabListLayout.rowSpacing) {
      ForEach(tabs, id: \.tabID) { tab in
        TabRow(tab: tab, isActive: tab.tabID == activeTabID)
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(
            tab.tabID == activeTabID ? [.isButton, .isSelected] : .isButton
          )
          .accessibilityAction { onSelect(tab.tabID) }
      }
    }
    .padding(TabListLayout.contentInset)
    .background(alignment: .topLeading) { highlight }
  }

  @ViewBuilder private var highlight: some View {
    if let row = tabs.firstIndex(where: { $0.tabID == highlightedTabID }) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.1))
        .frame(
          width: TabListLayout.panelWidth - 2 * TabListLayout.contentInset,
          height: TabListLayout.rowHeight)
        .offset(
          x: TabListLayout.contentInset,
          y: TabListLayout.contentInset + CGFloat(row) * TabListLayout.rowStep)
        .animation(.spring(duration: 0.22, bounce: 0.15), value: row)
    }
  }
}

private struct TabRow: View {
  let tab: FiberTabState
  let isActive: Bool

  var body: some View {
    HStack(spacing: 10) {
      icon
        .frame(width: 16, height: 16)
      Text(tab.title.isEmpty ? "Untitled" : tab.title)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
    }
    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
    .foregroundStyle(isActive ? .primary : .secondary)
    .padding(.horizontal, 10)
    .frame(height: TabListLayout.rowHeight)
  }

  @ViewBuilder private var icon: some View {
    if tab.isLoading {
      ProgressView()
        .controlSize(.small)
        .scaleEffect(0.75)
    } else if let favicon = tab.favicon {
      Image(nsImage: favicon)
        .resizable()
        .interpolation(.high)
    } else {
      Image(systemName: "globe")
        .foregroundStyle(.secondary)
    }
  }
}
