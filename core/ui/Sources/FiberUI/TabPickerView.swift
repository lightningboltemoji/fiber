import FiberBridge
import SwiftUI

/// Draws the tab picker: one piece of glass that is the bump on the window's
/// right edge while closed and grows into the panel when open, with the tab
/// list revealed inside it. Positions come from the model, in the picker's
/// coordinates; TabPicker handles all input.
struct TabPickerView: View {
  private static let panelCornerRadius: CGFloat = 22
  private static let rimWidth: CGFloat = 5

  let model: TabPickerModel

  var body: some View {
    let panel = model.panelRect
    let glass = model.isExpanded ? panel : model.bumpRect
    let cornerRadius =
      model.isExpanded ? Self.panelCornerRadius : TabPickerModel.bumpWidth / 2
    ZStack(alignment: .topLeading) {
      PanelShadow(cornerRadius: cornerRadius)
        .opacity(model.isExpanded ? 1 : 0)
        .frame(width: glass.width, height: glass.height)
        .offset(x: glass.minX, y: glass.minY)

      RimmedGlass(
        cornerRadius: cornerRadius,
        rimWidth: model.isExpanded ? Self.rimWidth : 0
      )
      .frame(width: glass.width, height: glass.height)
      .offset(x: glass.minX, y: glass.minY)
      .accessibilityElement()
      .accessibilityLabel("Tabs")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { model.onToggle() }

      // Laid out where the open panel is, and cut to the glass, so the glass
      // uncovers the list as it grows.
      TabPickerList(model: model)
        .frame(width: panel.width, height: panel.height, alignment: .top)
        .mask(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .frame(width: glass.width, height: glass.height)
            .offset(x: glass.minX - panel.minX, y: glass.minY - panel.minY)
        }
        .opacity(model.isExpanded ? 1 : 0)
        .offset(x: panel.minX, y: panel.minY)
        .accessibilityHidden(!model.isExpanded)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// Glass with a pronounced rim, like RimmedGlassView: a second layer of glass
/// inset inside the first.
private struct RimmedGlass: View {
  let cornerRadius: CGFloat
  let rimWidth: CGFloat

  var body: some View {
    Color.clear
      .glassEffect(
        .regular,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay {
        Color.clear
          .glassEffect(
            .regular,
            in: RoundedRectangle(
              cornerRadius: max(cornerRadius - rimWidth, 0),
              style: .continuous)
          )
          .padding(rimWidth)
      }
  }
}

/// A soft shadow around a rounded rect, like a window's, that stays outside
/// it so it doesn't darken the glass on top.
private struct PanelShadow: View {
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

/// The open panel's rows, with a highlight that glides to the tab under the
/// pointer.
private struct TabPickerList: View {
  let model: TabPickerModel

  var body: some View {
    VStack(spacing: TabPickerLayout.rowSpacing) {
      ForEach(model.tabs, id: \.tabID) { tab in
        TabPickerRow(tab: tab, isActive: tab.tabID == model.activeTabID)
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(
            tab.tabID == model.activeTabID ? [.isButton, .isSelected] : .isButton
          )
          .accessibilityAction { model.onSelect(tab.tabID) }
      }
    }
    .padding(TabPickerLayout.contentInset)
    .background(alignment: .topLeading) { highlight }
  }

  @ViewBuilder private var highlight: some View {
    if let row = model.tabs.firstIndex(where: {
      $0.tabID == model.highlightedTabID
    }) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.1))
        .frame(
          width: TabPickerModel.panelWidth - 2 * TabPickerLayout.contentInset,
          height: TabPickerLayout.rowHeight)
        .offset(
          x: TabPickerLayout.contentInset,
          y: TabPickerLayout.contentInset + CGFloat(row)
            * TabPickerLayout.rowStep)
        .animation(.spring(duration: 0.22, bounce: 0.15), value: row)
    }
  }
}

private struct TabPickerRow: View {
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
    .frame(height: TabPickerLayout.rowHeight)
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
