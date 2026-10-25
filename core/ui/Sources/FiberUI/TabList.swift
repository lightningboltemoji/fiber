import FiberBridge
import SwiftUI

/// The layout of a glass panel listing the tabs, the tab overlay's or a
/// notice's, shared by their hit testing and drawing.
enum TabListLayout {
  /// The notices'.
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

  /// The close button `point` (from the top-left of a list `width` wide, of
  /// the rows `rows`) is within reach of, the nearest if two are.
  static func closeButton(
    near point: CGPoint, in rows: [TabListRow.ID], width: CGFloat
  ) -> TabCloseButton? {
    guard !rows.isEmpty else {
      return nil
    }
    let row = min(
      max(Int(((point.y - rowCenter(0)) / rowStep).rounded()), 0),
      rows.count - 1)
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
    return TabCloseButton(rowID: rows[row], isHovered: button.contains(point))
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
  let rowID: TabListRow.ID
  /// Whether the pointer is on it, where a click closes the tab.
  let isHovered: Bool

  init(rowID: TabListRow.ID, isHovered: Bool) {
    self.rowID = rowID
    self.isHovered = isHovered
  }

  init(tabID: Int, isHovered: Bool) {
    self.init(rowID: .tab(tabID), isHovered: isHovered)
  }

  /// Its row's, if the row is a tab's.
  var tabID: Int? {
    if case .tab(let tabID) = rowID {
      return tabID
    }
    return nil
  }
}

/// A row of a tab list: one of the window's tabs, or a page kept on a shelf,
/// whose tab may not be open here.
struct TabListRow: Identifiable, Equatable {
  enum ID: Hashable {
    case tab(Int)
    case page(String)
  }

  let id: ID
  let title: String
  /// Formatted to read (see FiberTabState).
  let url: String
  let origin: String
  let favicon: NSImage?
  let isLoading: Bool
  /// The tab, if it's open here.
  let tabID: Int?

  init(tab: FiberTabState) {
    id = .tab(tab.tabID)
    title = tab.title
    url = tab.url
    origin = tab.origin
    favicon = tab.favicon
    isLoading = tab.isLoading
    tabID = tab.tabID
  }

  /// A shelf's page, as its tab shows it if it's open here.
  init(page: FiberPinState, tab: FiberTabState?) {
    id = .page(page.pinID)
    title = tab?.title ?? page.title
    url = tab?.url ?? page.url
    origin = tab?.origin ?? Self.origin(of: page.url)
    favicon = tab?.favicon ?? page.favicon
    isLoading = tab?.isLoading ?? false
    tabID = tab?.tabID
  }

  /// A shelf page without a tab here: dimmed, with a trash can for its close
  /// button, which removes the page.
  var isClosed: Bool { tabID == nil }

  /// The start of a URL formatted to read, through its host.
  private static func origin(of url: String) -> String {
    let host = url.range(of: "://")?.upperBound ?? url.startIndex
    return String(url[..<(url[host...].firstIndex(of: "/") ?? url.endIndex)])
  }
}

/// A panel's rows, with a highlight that glides to the highlighted row.
struct TabList: View {
  let width: CGFloat
  /// Whether each row shows its URL, after its title.
  var showsURL = false
  /// Whether each row shows its number, from 1, in its icon's place.
  var showsNumbers = false
  let rows: [TabListRow]
  let activeRowID: TabListRow.ID?
  let highlightedRowID: TabListRow.ID?
  let closeButton: TabCloseButton?
  /// A row being dragged: dimmed in its place while it's off the list, and
  /// while it's within it, lifted with its top here, from the list's.
  var draggedRowID: TabListRow.ID?
  var liftedRowTop: CGFloat?
  /// For accessibility, which presses a row to select it.
  let onSelect: (TabListRow.ID) -> Void
  /// For accessibility, which closes a row's tab without its button showing.
  let onClose: (TabListRow.ID) -> Void

  var body: some View {
    VStack(spacing: TabListLayout.rowSpacing) {
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
        let isDragged = row.id == draggedRowID
        let lift = isDragged ? liftedRowTop.map { $0 - rowTop(index) } : nil
        TabRow(
          row: row, showsURL: showsURL, number: index + 1,
          showsNumber: showsNumbers, isActive: row.id == activeRowID,
          closeButton: closeButton?.rowID == row.id ? closeButton : nil
        )
        .background {
          if lift != nil {
            LiftedRowBackground()
          }
        }
        .offset(y: lift ?? 0)
        .zIndex(lift != nil ? 1 : 0)
        .opacity(isDragged && lift == nil ? 0.3 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(
          row.id == activeRowID ? [.isButton, .isSelected] : .isButton
        )
        .accessibilityAction { onSelect(row.id) }
        .accessibilityAction(named: row.isClosed ? "Remove" : "Close Tab") {
          onClose(row.id)
        }
      }
    }
    .padding(TabListLayout.contentInset)
    .background(alignment: .topLeading) { highlight }
    // The others make room where a lifted row would drop.
    .animation(
      .spring(duration: 0.25, bounce: 0.1).slowMotion, value: rows.map(\.id))
  }

  private func rowTop(_ index: Int) -> CGFloat {
    TabListLayout.contentInset + CGFloat(index) * TabListLayout.rowStep
  }

  @ViewBuilder private var highlight: some View {
    if let row = rows.firstIndex(where: { $0.id == highlightedRowID }) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.1))
        .frame(
          width: width - 2 * TabListLayout.contentInset,
          height: TabListLayout.rowHeight)
        .offset(
          x: TabListLayout.contentInset,
          y: TabListLayout.contentInset + CGFloat(row) * TabListLayout.rowStep)
        .animation(.spring(duration: 0.22, bounce: 0.15).slowMotion, value: row)
    }
  }
}

/// Under a row lifted to a new place, like the highlight but raised.
private struct LiftedRowBackground: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(Color.primary.opacity(0.14))
      .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
  }
}

private struct TabRow: View {
  /// How long the close button takes to fade in or out.
  private static let closeButtonFade = Animation.easeInOut(duration: 0.25)
  /// How far ahead of the close button the title fades out.
  private static let titleFadeWidth: CGFloat = 16

  let row: TabListRow
  let showsURL: Bool
  let number: Int
  let showsNumber: Bool
  let isActive: Bool
  let closeButton: TabCloseButton?

  private var isClosed: Bool { row.isClosed }

  var body: some View {
    let isCloseButtonShown = closeButton != nil
    HStack(spacing: 10) {
      icon
        .frame(width: 16, height: 16)
        .saturation(isClosed ? 0 : 1)
        .opacity(showsNumber ? 0 : isClosed ? 0.5 : 1)
        .overlay {
          // Wider than the icon from 100 on.
          Text(String(number))
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
            .opacity(showsNumber ? 1 : 0)
            .accessibilityHidden(true)
        }
        .animation(
          .easeInOut(
            duration: showsNumber
              ? PaletteView.fadeInDuration : PaletteView.fadeOutDuration
          ).slowMotion, value: showsNumber)
      if showsURL {
        TitleAndURLLayout {
          title
          // The close button takes its place.
          Group {
            Text(row.origin)
              .accessibilityLabel(row.url)
            Text(row.url.dropFirst(row.origin.count))
              .truncationMode(.middle)
              // Narrower than its ellipsis, it shows nothing.
              .frame(minWidth: 0, alignment: .leading)
              .clipped()
              .accessibilityHidden(true)
          }
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .animation(Self.closeButtonFade.slowMotion) {
            $0.opacity(isCloseButtonShown ? 0 : 1)
          }
        }
      } else {
        title
        Spacer(minLength: 0)
      }
    }
    // Text that changes as the row resizes, a title truncating further,
    // changes in place: a crossfade's would travel apart from the row.
    .contentTransition(.identity)
    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
    .foregroundStyle(
      isActive ? .primary : isClosed ? HierarchicalShapeStyle.tertiary : .secondary)
    .animation(.easeInOut(duration: 0.25).slowMotion, value: isClosed)
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
          .animation(Self.closeButtonFade.slowMotion) {
            $0.opacity(isCloseButtonShown ? 0 : 1)
          }
      }
    }
    .overlay(alignment: .trailing) {
      Image(systemName: isClosed ? "trash" : "xmark")
        .font(.system(size: isClosed ? 11 : 10, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
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
        .animation(Self.closeButtonFade.slowMotion) {
          $0.opacity(isCloseButtonShown ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
  }

  private var title: some View {
    Text(row.title.isEmpty ? "Untitled" : row.title)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  @ViewBuilder private var icon: some View {
    if row.isLoading {
      ProgressView()
        .controlSize(.small)
        .scaleEffect(0.75)
    } else if let favicon = row.favicon {
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

/// A row's title, then its URL against the row's end: the URL's origin whole,
/// as much of the title as fits beside it, then as much of the rest of the URL
/// as fits in what's left.
private struct TitleAndURLLayout: Layout {
  /// Between the title and the URL.
  private static let spacing: CGFloat = 20
  /// The least of the rest of the URL worth showing, short of all of it.
  private static let minPathWidth: CGFloat = 40

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    return CGSize(
      width: proposal.width ?? sizes.map(\.width).reduce(Self.spacing, +),
      height: sizes.map(\.height).max() ?? 0)
  }

  /// `subviews` are the title, the URL's origin and the rest of the URL.
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
    cache: inout ()
  ) {
    let (title, origin, path) = (subviews[0], subviews[1], subviews[2])
    let originWidth = min(
      origin.sizeThatFits(.unspecified).width, bounds.width)
    let titleWidth = min(
      title.sizeThatFits(.unspecified).width,
      max(bounds.width - originWidth - (originWidth > 0 ? Self.spacing : 0), 0))
    let fullPathWidth = path.sizeThatFits(.unspecified).width
    var pathWidth = min(
      fullPathWidth,
      max(bounds.width - titleWidth - Self.spacing - originWidth, 0))
    if pathWidth < min(fullPathWidth, Self.minPathWidth) {
      pathWidth = 0
    }
    pathWidth = path.sizeThatFits(.init(width: pathWidth, height: nil)).width

    title.place(
      at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
      proposal: .init(width: titleWidth, height: nil))
    origin.place(
      at: CGPoint(x: bounds.maxX - pathWidth, y: bounds.midY),
      anchor: .trailing, proposal: .init(width: originWidth, height: nil))
    path.place(
      at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
      proposal: .init(width: pathWidth, height: nil))
  }
}
