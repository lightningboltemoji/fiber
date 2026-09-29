import FiberBridge
import SwiftUI

/// Draws the tab picker; TabPicker handles all input. One piece of glass is
/// the bump on the window's right edge while closed and grows into the panel
/// when open, uncovering the tab list inside it. Positions come from the
/// model, in the picker's coordinates.
struct TabPickerView: View {
  let model: TabPickerModel

  var body: some View {
    let panel = model.panelRect
    let glass = model.isExpanded ? panel : model.bumpRect
    let cornerRadius =
      model.isExpanded
      ? TabListLayout.cornerRadius : TabPickerModel.bumpWidth / 2
    ZStack(alignment: .topLeading) {
      PanelShadow(cornerRadius: cornerRadius)
        .opacity(model.isExpanded ? 1 : 0)
        .frame(width: glass.width, height: glass.height)
        .offset(x: glass.minX, y: glass.minY)

      RimmedGlass(
        cornerRadius: cornerRadius,
        rimWidth: model.isExpanded ? TabListLayout.rimWidth : 0
      )
      .frame(width: glass.width, height: glass.height)
      .offset(x: glass.minX, y: glass.minY)
      .accessibilityElement()
      .accessibilityLabel("Tabs")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { model.onToggle() }
      .accessibilityHidden(!model.isPanelEnabled)

      // Laid out where the open panel is, and cut to the glass, so the glass
      // uncovers the list as it grows.
      TabList(
        tabs: model.tabs, activeTabID: model.activeTabID,
        highlightedTabID: model.highlightedTabID, onSelect: model.onSelect
      )
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

