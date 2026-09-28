import FiberBridge
import SwiftUI

/// Draws the tab picker. The open panel comes out of the page's gutter like a
/// drop of glass: it appears at the pointer, stretches out of the gutter,
/// then spreads up and down into the panel, bouncing as it settles, with the
/// tab list uncovered inside it. Closing runs it backwards, out of sight.
/// Positions come from the model, in the picker's coordinates; TabPicker
/// handles all input.
struct TabPickerView: View {
  /// The drop's size, in the gutter.
  private static let dropSize: CGFloat = 8

  let model: TabPickerModel

  var body: some View {
    let panel = model.panelRect
    let gutter = model.gutterRect
    ZStack(alignment: .topLeading) {
      // What accessibility presses to open the panel.
      Color.clear
        .frame(width: gutter.width, height: gutter.height)
        .offset(x: gutter.minX, y: gutter.minY)
        .accessibilityElement()
        .accessibilityLabel("Tabs")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.onToggle() }
        // While the toolbar's sidebar lists the tabs, there's no panel.
        .accessibilityHidden(!model.isPanelEnabled)

      // In the panel's own coordinates, so the drop's animations leave the
      // panel's position alone, which scrolling moves.
      droplet
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .offset(x: panel.minX, y: panel.minY)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var droplet: some View {
    let panel = model.panelRect
    let isOpen = model.isExpanded
    // At the pointer (the active tab's row) in the gutter.
    let dropCenter = CGPoint(
      x: model.gutterRect.midX - panel.minX,
      y: TabListLayout.rowCenter(model.activeRow))
    let drop = CGRect(
      x: dropCenter.x - Self.dropSize / 2, y: dropCenter.y - Self.dropSize / 2,
      width: Self.dropSize, height: Self.dropSize)
    let glass = isOpen ? CGRect(origin: .zero, size: panel.size) : drop
    let cornerRadius = isOpen ? TabListLayout.cornerRadius : Self.dropSize / 2
    // Out of the gutter, then up and down; closing, the other way around.
    let across: Animation =
      isOpen
      ? .spring(duration: 0.34, bounce: 0.32)
      : .spring(duration: 0.26).delay(0.08)
    let along: Animation =
      isOpen
      ? .spring(duration: 0.52, bounce: 0.3).delay(0.07)
      : .spring(duration: 0.26)
    return ZStack(alignment: .topLeading) {
      ZStack {
        PanelShadow(cornerRadius: cornerRadius)
          .opacity(isOpen ? 1 : 0)
        RimmedGlass(
          cornerRadius: cornerRadius,
          rimWidth: isOpen ? TabListLayout.rimWidth : 0)
      }
      .accessibilityHidden(true)
      .stretched(to: glass, across: across, along: along, value: isOpen)
      .opacity(isOpen ? 1 : 0)
      .animation(.easeOut(duration: 0.12), value: isOpen)

      TabList(
        tabs: model.tabs, activeTabID: model.activeTabID,
        highlightedTabID: model.highlightedTabID, onSelect: model.onSelect
      )
      .frame(width: panel.width, height: panel.height, alignment: .top)
      .mask(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stretched(to: glass, across: across, along: along, value: isOpen)
      }
      .opacity(isOpen ? 1 : 0)
      .animation(
        isOpen
          ? .easeOut(duration: 0.2).delay(0.12) : .easeOut(duration: 0.1),
        value: isOpen)
      .accessibilityHidden(!isOpen)
    }
  }
}

extension View {
  /// Sizes the view to `rect` and moves it there, animating its width and
  /// position across (`across`) apart from its height and position along
  /// (`along`), when `value` changes.
  fileprivate func stretched(
    to rect: CGRect, across: Animation, along: Animation, value: Bool
  ) -> some View {
    frame(width: rect.width)
      .offset(x: rect.minX)
      .animation(across, value: value)
      .frame(height: rect.height, alignment: .top)
      .offset(y: rect.minY)
      .animation(along, value: value)
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

