import FiberBridge
import SwiftUI

/// Draws the tab picker; TabPicker handles all input. One piece of glass is
/// the lip, and the drop hanging from it that grows into the column, its tabs
/// condensing out of the glass as it pours over them; the highlighted tab's
/// preview hangs beside it in its own. Positions come from the model, in the
/// picker's coordinates.
struct TabPickerView: View {
  private static let closeFade = Animation.easeOut(duration: 0.12)

  let model: TabPickerModel

  var body: some View {
    let drop = model.drop
    let shape = drop.shape
    ZStack(alignment: .topLeading) {
      PanelShadow(shape: shape)
        .opacity(drop.shadowOpacity)

      RimmedGlass(shape: shape, rimWidth: drop.rimWidth)
        .accessibilityHidden(true)

      // The glass fills the picker, so it's framed around the drop for
      // accessibility.
      let frame = shape.path(in: .zero).boundingRect
      Color.clear
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .accessibilityElement()
        .accessibilityLabel("Tabs")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.onToggle() }

      // Laid out where the open column is, and cut to the glass, so the glass
      // uncovers the tabs as it pours. Closing, they fade before it narrows
      // across them.
      TabPickerItems(model: model)
        .mask { shape }
        .opacity(model.isExpanded ? 1 : 0)
        .animation(
          model.isExpanded ? nil : Self.closeFade.slowMotion,
          value: model.isExpanded)
        .accessibilityHidden(!model.isExpanded)

      TabPreview(model: model)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// The column's tabs, with a highlight that glides to the highlighted one.
private struct TabPickerItems: View {
  let model: TabPickerModel

  var body: some View {
    let columnMinX = model.columnMinX
    ZStack(alignment: .topLeading) {
      highlight
      let shown = Array(model.tabs.prefix(model.maxRows).enumerated())
      ForEach(shown, id: \.element.tabID) { index, tab in
        let frame = TabPickerLayout.itemFrame(index, columnMinX: columnMinX)
        let coverage = model.coverage(ofRow: index)
        if coverage > 0 {
          TabPickerItem(
            tab: tab, isActive: tab.tabID == model.activeTabID,
            closeButton: model.closeButton?.tabID == tab.tabID
              ? model.closeButton : nil
          )
          .frame(width: frame.width, height: frame.height)
          .modifier(Condensing(coverage: coverage))
          .offset(x: frame.minX, y: frame.minY)
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(
            tab.tabID == model.activeTabID ? [.isButton, .isSelected] : .isButton
          )
          .accessibilityAction { model.onSelect(tab.tabID) }
          .accessibilityAction(named: "Close Tab") { model.onClose(tab.tabID) }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder private var highlight: some View {
    if let index = model.highlightedIndex {
      let frame = TabPickerLayout.itemFrame(index, columnMinX: model.columnMinX)
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.1))
        .frame(width: frame.width, height: frame.height)
        .opacity(Condensing.eased(model.coverage(ofRow: index)))
        .offset(x: frame.minX, y: frame.minY)
        .animation(.spring(duration: 0.22, bounce: 0.15).slowMotion, value: index)
    }
  }
}

/// A tab coming out of the glass as it pours over: drifting down into place
/// as it sharpens and brightens.
private struct Condensing: ViewModifier {
  /// How far above its place, and how blurred, a tab is as the glass first
  /// reaches it.
  private static let rise: CGFloat = 8
  private static let blur: CGFloat = 5
  private static let scale: CGFloat = 0.94

  let coverage: CGFloat

  static func eased(_ coverage: CGFloat) -> CGFloat {
    coverage * coverage * (3 - 2 * coverage)
  }

  func body(content: Content) -> some View {
    let progress = Self.eased(coverage)
    let remaining = 1 - progress
    content
      .scaleEffect(1 - (1 - Self.scale) * remaining, anchor: .top)
      .blur(radius: Self.blur * remaining)
      .opacity(progress)
      .offset(y: -Self.rise * remaining)
  }
}

/// A tab's icon, then its title over its host, whose end gives way to the
/// close button.
private struct TabPickerItem: View {
  private static let closeButtonFade = Animation.easeInOut(duration: 0.25)
  /// How far ahead of the close button the text fades out.
  private static let textFadeWidth: CGFloat = 16

  let tab: FiberTabState
  let isActive: Bool
  let closeButton: TabCloseButton?

  var body: some View {
    let isCloseButtonShown = closeButton != nil
    HStack(spacing: 10) {
      icon
        .frame(width: 16, height: 16)
      VStack(alignment: .leading, spacing: 1) {
        Text(tab.title.isEmpty ? "Untitled" : tab.title)
          .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
          .foregroundStyle(isActive ? .primary : .secondary)
        Text(tab.origin.isEmpty ? tab.url : tab.origin)
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .truncationMode(.middle)
      }
      .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .mask {
      HStack(spacing: 0) {
        Rectangle()
        LinearGradient(
          colors: [.black, .clear], startPoint: .leading, endPoint: .trailing
        )
        .frame(width: Self.textFadeWidth)
        Color.clear
          .frame(
            width: TabPickerLayout.closeButtonInset
              + TabPickerLayout.closeButtonSize)
      }
      .overlay {
        Rectangle()
          .animation(Self.closeButtonFade.slowMotion) {
            $0.opacity(isCloseButtonShown ? 0 : 1)
          }
      }
    }
    .overlay(alignment: .trailing) {
      Image(systemName: "xmark")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(closeButton?.isHovered == true ? .primary : .secondary)
        .frame(
          width: TabPickerLayout.closeButtonSize,
          height: TabPickerLayout.closeButtonSize
        )
        .background {
          Circle()
            .fill(Color.primary.opacity(0.1))
            .opacity(closeButton?.isHovered == true ? 1 : 0)
        }
        .padding(.trailing, TabPickerLayout.closeButtonInset)
        .animation(Self.closeButtonFade.slowMotion) {
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

/// The highlighted tab's page in its own glass beside it, gliding from tab
/// to tab, and fading where it was when there's none to show.
private struct TabPreview: View {
  private static let spring = Animation.spring(duration: 0.3, bounce: 0.12)

  let model: TabPickerModel
  @State private var lastRect: CGRect?
  @State private var lastImage: NSImage?
  /// It glides only once it's showing; it appears in place.
  @State private var wasShown = false

  var body: some View {
    let rect = model.previewRect
    let isShown = rect != nil
    let shown = rect ?? lastRect ?? .zero
    let thumbnail = TabPickerLayout.thumbnailSize
    let shape = RoundedRectangle(
      cornerRadius: TabPickerLayout.cornerRadius - TabPickerLayout.previewInset,
      style: .continuous)
    ZStack(alignment: .topLeading) {
      PanelShadow(cornerRadius: TabPickerLayout.cornerRadius)
      RimmedGlass(
        cornerRadius: TabPickerLayout.cornerRadius,
        rimWidth: TabPickerLayout.rimWidth)
      if let image = isShown ? model.preview : lastImage {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fill)
          .frame(
            width: thumbnail.width, height: thumbnail.height, alignment: .top
          )
          .clipShape(shape)
          .overlay {
            shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
          }
          .padding(TabPickerLayout.previewInset)
      }
    }
    .animation(Self.spring.slowMotion) {
      $0.scaleEffect(
        isShown ? 1 : 0.94,
        anchor: model.isPreviewLeading ? .topTrailing : .topLeading
      )
      .opacity(isShown ? 1 : 0)
    }
    .frame(width: shown.width, height: shown.height, alignment: .topLeading)
    .offset(x: shown.minX, y: shown.minY)
    .animation(wasShown && isShown ? Self.spring.slowMotion : nil, value: shown)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: rect) { _, rect in
      if rect != nil {
        lastRect = rect
        lastImage = model.preview
      }
    }
    .onChange(of: model.highlightedTabID) {
      if isShown {
        lastImage = model.preview
      }
    }
    .onChange(of: isShown) { _, isShown in wasShown = isShown }
  }
}

/// A soft shadow around a shape, like a window's, that stays outside it so
/// it doesn't darken the glass on top.
struct PanelShadow<S: Shape>: View {
  let shape: S

  var body: some View {
    shape
      .fill(.black)
      .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
      .mask {
        Rectangle()
          .padding(-60)
          .overlay { shape.blendMode(.destinationOut) }
          .compositingGroup()
      }
  }
}

extension PanelShadow where S == RoundedRectangle {
  init(cornerRadius: CGFloat) {
    self.init(
      shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}
