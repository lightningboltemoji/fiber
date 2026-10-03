import FiberBridge
import SwiftUI

/// The layout of a glass panel listing the tabs, the tab picker's or the tab
/// overlay's, shared by their hit testing and drawing.
enum TabListLayout {
  /// The tab picker's.
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

  /// A row's close button is a square this wide at the row's right end, as
  /// far in from it as from the row's top and bottom.
  static let closeButtonSize: CGFloat = 24
  static var closeButtonInset: CGFloat { (rowHeight - closeButtonSize) / 2 }
  /// How near the pointer comes to a close button for it to show.
  static let closeButtonReach: CGFloat = 10

  /// The center of row `row`, from the panel's top.
  static func rowCenter(_ row: Int) -> CGFloat {
    contentInset + CGFloat(row) * rowStep + rowHeight / 2
  }

  /// The close button `point` (from the top-left of a list `width` wide) is
  /// within reach of, the nearest if two are.
  static func closeButton(
    near point: CGPoint, in tabs: [FiberTabState], width: CGFloat
  ) -> TabCloseButton? {
    guard !tabs.isEmpty else {
      return nil
    }
    let row = min(
      max(Int(((point.y - rowCenter(0)) / rowStep).rounded()), 0),
      tabs.count - 1)
    let button = CGRect(
      x: width - contentInset - closeButtonInset - closeButtonSize,
      y: rowCenter(row) - closeButtonSize / 2, width: closeButtonSize,
      height: closeButtonSize)
    guard
      button.insetBy(dx: -closeButtonReach, dy: -closeButtonReach).contains(
        point)
    else {
      return nil
    }
    return TabCloseButton(
      tabID: tabs[row].tabID, isHovered: button.contains(point))
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

/// The one close button a tab list shows: the one the pointer is near.
struct TabCloseButton: Equatable {
  let tabID: Int
  /// Whether the pointer is on it, where a click closes the tab.
  let isHovered: Bool
}

/// A panel's rows, with a highlight that glides to the highlighted tab.
struct TabList: View {
  let width: CGFloat
  /// Whether each row shows its URL, after its title.
  var showsURL = false
  let tabs: [FiberTabState]
  let activeTabID: Int
  let highlightedTabID: Int?
  let closeButton: TabCloseButton?
  /// For accessibility, which presses a tab to select it.
  let onSelect: (Int) -> Void
  /// For accessibility, which closes a tab without its button showing.
  let onClose: (Int) -> Void

  var body: some View {
    VStack(spacing: TabListLayout.rowSpacing) {
      ForEach(tabs, id: \.tabID) { tab in
        TabRow(
          tab: tab, showsURL: showsURL, isActive: tab.tabID == activeTabID,
          closeButton: closeButton?.tabID == tab.tabID ? closeButton : nil
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(
          tab.tabID == activeTabID ? [.isButton, .isSelected] : .isButton
        )
        .accessibilityAction { onSelect(tab.tabID) }
        .accessibilityAction(named: "Close Tab") { onClose(tab.tabID) }
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
          width: width - 2 * TabListLayout.contentInset,
          height: TabListLayout.rowHeight)
        .offset(
          x: TabListLayout.contentInset,
          y: TabListLayout.contentInset + CGFloat(row) * TabListLayout.rowStep)
        .animation(.spring(duration: 0.22, bounce: 0.15), value: row)
    }
  }
}

private struct TabRow: View {
  /// How long the close button takes to fade in or out.
  private static let closeButtonFade = Animation.easeInOut(duration: 0.25)
  /// How far ahead of the close button the title fades out.
  private static let titleFadeWidth: CGFloat = 16

  let tab: FiberTabState
  let showsURL: Bool
  let isActive: Bool
  let closeButton: TabCloseButton?

  var body: some View {
    let isCloseButtonShown = closeButton != nil
    HStack(spacing: 10) {
      icon
        .frame(width: 16, height: 16)
      Text(tab.title.isEmpty ? "Untitled" : tab.title)
        .lineLimit(1)
        .truncationMode(.tail)
        .layoutPriority(1)
      Spacer(minLength: 0)
      if showsURL {
        // The close button takes its place.
        Text(tab.url)
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 220, alignment: .trailing)
          .animation(Self.closeButtonFade) {
            $0.opacity(isCloseButtonShown ? 0 : 1)
          }
      }
    }
    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
    .foregroundStyle(isActive ? .primary : .secondary)
    .padding(.horizontal, 10)
    .frame(height: TabListLayout.rowHeight)
    .mask {
      HStack(spacing: 0) {
        Rectangle()
        LinearGradient(
          colors: [.black, .clear], startPoint: .leading, endPoint: .trailing
        )
        .frame(width: Self.titleFadeWidth)
        Color.clear
          .frame(
            width: TabListLayout.closeButtonInset
              + TabListLayout.closeButtonSize)
      }
      .overlay {
        Rectangle()
          .animation(Self.closeButtonFade) {
            $0.opacity(isCloseButtonShown ? 0 : 1)
          }
      }
    }
    .overlay(alignment: .trailing) {
      Image(systemName: "xmark")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(closeButton?.isHovered == true ? .primary : .secondary)
        .frame(
          width: TabListLayout.closeButtonSize,
          height: TabListLayout.closeButtonSize
        )
        .background {
          Circle()
            .fill(Color.primary.opacity(0.1))
            .opacity(closeButton?.isHovered == true ? 1 : 0)
        }
        .padding(.trailing, TabListLayout.closeButtonInset)
        .animation(Self.closeButtonFade) {
          $0.opacity(isCloseButtonShown ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder private var icon: some View {
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
  }
}
