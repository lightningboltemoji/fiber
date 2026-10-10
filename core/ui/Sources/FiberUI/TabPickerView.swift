import FiberBridge
import SwiftUI

/// Draws the tab picker; TabPicker handles all input. One piece of glass is
/// the lip while closed and grows into the strip, uncovering the tabs; the
/// highlighted tab's preview hangs below in its own. Positions come from the
/// model, in the picker's coordinates.
struct TabPickerView: View {
  let model: TabPickerModel

  var body: some View {
    let panel = model.panelRect
    let glass = model.isExpanded ? panel : model.lipRect
    let cornerRadius =
      model.isExpanded
      ? TabPickerLayout.cornerRadius : TabPickerModel.lipHeight / 2
    // An overlay, so a strip wider than the window runs off its right edge
    // rather than the hosting view centering it.
    Color.clear.overlay(alignment: .topLeading) {
      ZStack(alignment: .topLeading) {
        PanelShadow(cornerRadius: cornerRadius)
          .opacity(model.isExpanded ? 1 : 0)
          .frame(width: glass.width, height: glass.height)
          .offset(x: glass.minX, y: glass.minY)

        RimmedGlass(
          cornerRadius: cornerRadius,
          rimWidth: model.isExpanded ? TabPickerLayout.rimWidth : 0
        )
        .frame(width: glass.width, height: glass.height)
        .offset(x: glass.minX, y: glass.minY)
        .accessibilityElement()
        .accessibilityLabel("Tabs")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.onToggle() }

        // Laid out where the open strip is, and cut to the glass, so the
        // glass uncovers the tabs as it grows.
        TabPickerItems(model: model)
          .frame(width: panel.width, height: panel.height, alignment: .topLeading)
          .mask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .frame(width: glass.width, height: glass.height)
              .offset(x: glass.minX - panel.minX, y: glass.minY - panel.minY)
          }
          .opacity(model.isExpanded ? 1 : 0)
          .offset(x: panel.minX, y: panel.minY)
          .accessibilityHidden(!model.isExpanded)

        TabPreview(model: model)
      }
    }
  }
}

/// The strip's tabs, with a highlight that glides to the highlighted one.
private struct TabPickerItems: View {
  let model: TabPickerModel

  var body: some View {
    ZStack(alignment: .topLeading) {
      highlight
      ForEach(Array(model.tabs.enumerated()), id: \.element.tabID) {
        index, tab in
        let frame = TabPickerLayout.itemFrame(index)
        TabPickerItem(
          tab: tab, isActive: tab.tabID == model.activeTabID,
          closeButton: model.closeButton?.tabID == tab.tabID
            ? model.closeButton : nil
        )
        .frame(width: frame.width, height: frame.height)
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

  @ViewBuilder private var highlight: some View {
    if let index = model.highlightedIndex {
      let frame = TabPickerLayout.itemFrame(index)
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.1))
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .animation(.spring(duration: 0.22, bounce: 0.15).slowMotion, value: index)
    }
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
    HStack(spacing: 9) {
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

/// The highlighted tab's page in its own glass under it, gliding from tab to
/// tab, and fading where it was when there's none to show.
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
      $0.scaleEffect(isShown ? 1 : 0.94, anchor: .top)
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

/// A soft shadow around a rounded rect, like a window's, that stays outside
/// it so it doesn't darken the glass on top.
struct PanelShadow: View {
  let cornerRadius: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
