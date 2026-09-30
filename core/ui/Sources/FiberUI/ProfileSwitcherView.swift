import AppKit
import SwiftUI

/// What the profile switcher's ring holds: the profiles, then ways to add one.
struct OrbitItem: Identifiable {
  enum ID: Hashable {
    case profile(String)
    case newProfile
    case importProfile
  }

  let id: ID
  let title: String
  /// A profile's avatar; the others show `symbolName`.
  var avatar: NSImage?
  var symbolName: String?
  var isCurrent = false
}

/// An avatar a new profile can have.
struct AvatarOption: Identifiable {
  let id: Int
  let image: NSImage
  let label: String
}

/// A profile in another browser that can be imported.
struct ImportSource: Identifiable {
  let id: Int
  let name: String
  /// Under the name: its account, say.
  let detail: String
  let avatar: NSImage?
}

/// The profile switcher's geometry. Sizes are at a scale of 1; the switcher
/// shrinks as a whole when the window is too small for its ring.
enum OrbitLayout {
  static let minRadius: CGFloat = 200
  /// Along the ring, from one item's center to the next, at least, so their
  /// names don't collide.
  static let itemSpacing: CGFloat = 160
  static let hubDiameter: CGFloat = 136
  static let itemDiameter: CGFloat = 95
  static let avatarDiameter: CGFloat = 75
  static let symbolSize: CGFloat = 32
  static let badgeSize: CGFloat = 24
  static let labelGap: CGFloat = 8
  static let labelHeight: CGFloat = 19
  /// Between the ring's items and the window's edges.
  static let margin: CGFloat = 32
  /// Seconds for the ring to go around once.
  static let period: TimeInterval = 160
  /// How long items take to come out from the hub, and how much later each
  /// starts than the one before.
  static let emergeDuration: TimeInterval = 0.7
  static let emergeStagger: TimeInterval = 0.045
  static let retractDuration: TimeInterval = 0.2
  static let panelWidth: CGFloat = 440
  static let panelCornerRadius: CGFloat = 34
  /// Glass nearer each other than this melts together, as items do coming
  /// out of the hub.
  static let meltDistance: CGFloat = 24

  static func radius(count: Int) -> CGFloat {
    max(minRadius, CGFloat(count) * itemSpacing / (2 * .pi))
  }

  /// The scale that fits a ring of `radius` in `size`.
  static func scale(radius: CGFloat, in size: CGSize) -> CGFloat {
    let reach =
      radius + itemDiameter / 2 + labelGap + labelHeight + margin
    guard size.width > 0, size.height > 0 else {
      return 1
    }
    return min(1, min(size.width, size.height) / (2 * reach))
  }
}

/// What the profile switcher shows. ProfileSwitcherOverlay handles the
/// keyboard and the ring's motion, and ProfileSwitcherView draws it and takes
/// clicks.
@MainActor
@Observable
final class ProfileSwitcherModel {
  enum Page: Equatable {
    case orbit
    case newProfile
    case importProfile
  }

  enum ImportState: Equatable {
    case choosing
    case importing(String)
    case failed(String)
  }

  var items: [OrbitItem] = []
  var page = Page.orbit
  var size = CGSize.zero
  /// How far the ring has turned, in radians, clockwise.
  var turn: Double = 0
  /// The display's clock, which times items coming out of the hub and going
  /// back in.
  var time: CFTimeInterval = 0
  var openedAt: CFTimeInterval?
  var closedAt: CFTimeInterval?
  var hoveredID: OrbitItem.ID?
  /// Chosen with the arrow keys.
  var selectedID: OrbitItem.ID?

  var avatars: [AvatarOption] = []
  var newProfileName = ""
  var newProfileAvatarID: Int?

  /// What importing is called, like "Import from Chrome", and the browser's
  /// icon.
  var importTitle = ""
  var importIcon: NSImage?
  var importSources: [ImportSource] = []
  var importSourceID: Int?
  var importState = ImportState.choosing

  var onPick: (OrbitItem.ID) -> Void = { _ in }
  var onDismiss: () -> Void = {}
  var onCreate: (_ name: String, _ avatarID: Int?) -> Void = { _, _ in }
  var onImport: (_ sourceID: Int) -> Void = { _ in }
  /// The page changed; the keyboard focus goes where it now belongs.
  var onPageChange: (Page) -> Void = { _ in }

  var radius: CGFloat { OrbitLayout.radius(count: items.count) }
  var scale: CGFloat { OrbitLayout.scale(radius: radius, in: size) }
  var isHeld: Bool { hoveredID != nil || selectedID != nil }

  /// How far item `index` has come out of the hub, from 0 to a little past 1
  /// (it overshoots, then settles).
  func emergence(ofItemAt index: Int) -> CGFloat {
    guard let openedAt else {
      return 0
    }
    let start = openedAt + Double(index) * OrbitLayout.emergeStagger
    var amount = backOut(clamp((time - start) / OrbitLayout.emergeDuration))
    if let closedAt {
      amount *= 1 - easeIn(clamp((time - closedAt) / OrbitLayout.retractDuration))
    }
    return amount
  }

  /// Where item `index` is, from the hub's center.
  func offset(ofItemAt index: Int) -> CGSize {
    let angle = turn + 2 * .pi * Double(index) / Double(items.count) - .pi / 2
    let distance = radius * emergence(ofItemAt: index)
    return CGSize(width: distance * cos(angle), height: distance * sin(angle))
  }

  func show(_ page: Page, animated: Bool = true) {
    guard page != self.page else {
      return
    }
    hoveredID = nil
    if animated {
      withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
        self.page = page
      }
    } else {
      self.page = page
    }
    onPageChange(page)
  }

  func create() {
    let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      return
    }
    onCreate(name, newProfileAvatarID)
  }

  func startImport() {
    if case .importing = importState {
      return
    }
    guard let importSourceID else {
      return
    }
    onImport(importSourceID)
  }

  private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }

  private func backOut(_ t: Double) -> Double {
    let overshoot = 1.4
    let u = t - 1
    return 1 + (overshoot + 1) * u * u * u + overshoot * u * u
  }

  private func easeIn(_ t: Double) -> Double {
    t * t
  }
}

struct ProfileSwitcherView: View {
  let model: ProfileSwitcherModel

  var body: some View {
    ZStack {
      // A click on nothing leaves: the switcher from the ring, the ring from
      // a page.
      Color.clear
        .contentShape(.rect)
        .onTapGesture {
          if model.page == .orbit {
            model.onDismiss()
          } else {
            model.show(.orbit)
          }
        }
        .accessibilityHidden(true)

      GlassEffectContainer(spacing: OrbitLayout.meltDistance) {
        switch model.page {
        case .orbit:
          Orbit(model: model)
        case .newProfile:
          NewProfilePanel(model: model)
        case .importProfile:
          ImportPanel(model: model)
        }
      }
      .scaleEffect(model.scale)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.colorScheme, .dark)
  }
}

/// The hub, and the items turning around it.
private struct Orbit: View {
  let model: ProfileSwitcherModel

  var body: some View {
    let spread = model.items.indices.map(model.emergence(ofItemAt:)).max() ?? 0
    ZStack {
      Circle()
        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        .frame(width: 2 * model.radius, height: 2 * model.radius)
        .scaleEffect(max(spread, 0.001))
        .opacity(min(spread, 1))
        .accessibilityHidden(true)

      Text("Profiles")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: OrbitLayout.hubDiameter, height: OrbitLayout.hubDiameter)
        .glassEffect(.regular, in: .circle)
        .accessibilityAddTraits(.isHeader)

      ForEach(Array(model.items.enumerated()), id: \.element.id) {
        index, item in
        let emergence = model.emergence(ofItemAt: index)
        OrbitBubble(
          item: item,
          isHovered: model.hoveredID == item.id,
          isSelected: model.selectedID == item.id,
          scale: 0.35 + 0.65 * emergence,
          contentOpacity: max(0, min(1, (emergence - 0.25) / 0.35)),
          labelOpacity: max(0, min(1, (emergence - 0.6) / 0.4))
        ) {
          model.onPick(item.id)
        }
        .onHover { hovering in
          if hovering {
            model.hoveredID = item.id
          } else if model.hoveredID == item.id {
            model.hoveredID = nil
          }
        }
        .offset(model.offset(ofItemAt: index))
      }
    }
  }
}

private struct OrbitBubble: View {
  private static let hoverScale: CGFloat = 1.08

  let item: OrbitItem
  let isHovered: Bool
  let isSelected: Bool
  /// Its size, as it comes out of the hub.
  let scale: CGFloat
  /// The avatar or symbol's, which stays hidden while the glass is still in
  /// the hub's.
  let contentOpacity: CGFloat
  let labelOpacity: CGFloat
  let action: () -> Void

  var body: some View {
    // Sized by its frame, not scaleEffect: the glass container scales glass
    // from its corner and the content from its center.
    let diameter =
      OrbitLayout.itemDiameter * scale * (isHovered ? Self.hoverScale : 1)
    Button(action: action) {
      ZStack {
        if let avatar = item.avatar {
          Image(nsImage: avatar)
            .resizable()
            .scaledToFill()
            .frame(
              width: OrbitLayout.avatarDiameter,
              height: OrbitLayout.avatarDiameter
            )
            .clipShape(.circle)
        } else if let symbolName = item.symbolName {
          Image(systemName: symbolName)
            .font(.system(size: OrbitLayout.symbolSize, weight: .medium))
            .foregroundStyle(.white)
        }
      }
      .frame(width: OrbitLayout.itemDiameter, height: OrbitLayout.itemDiameter)
      // In the glass's content: the glass draws over what's overlaid on it.
      .overlay(alignment: .bottomTrailing) {
        if item.isCurrent {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: OrbitLayout.badgeSize))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .offset(x: 2, y: 2)
            .accessibilityHidden(true)
        }
      }
      .opacity(contentOpacity)
      .scaleEffect(diameter / OrbitLayout.itemDiameter)
      .frame(width: diameter, height: diameter)
      .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .circle)
    .overlay {
      Circle()
        .strokeBorder(.white, lineWidth: 2)
        .padding(-5)
        .opacity(isSelected ? 1 : 0)
    }
    // Under the bubble, without moving it off the ring.
    .overlay {
      Text(item.title)
        .font(.system(size: 14, weight: item.isCurrent ? .semibold : .medium))
        .foregroundStyle(.white.opacity(isHovered || isSelected ? 1 : 0.85))
        .lineLimit(1)
        .fixedSize()
        .offset(
          y: diameter / 2 + OrbitLayout.labelGap + OrbitLayout.labelHeight / 2
        )
        .opacity(labelOpacity)
        .accessibilityHidden(true)
    }
    .animation(.spring(duration: 0.3, bounce: 0.3), value: isHovered)
    .accessibilityLabel(
      item.isCurrent ? "\(item.title), current profile" : item.title)
  }
}

/// A button whose key is after its title, fainter, as VeilPrompt's are.
private struct KeyedButtonLabel: View {
  let title: String
  let key: String

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
      Text(key)
        .font(.system(size: 12, weight: .medium))
        .opacity(0.55)
    }
    .frame(minWidth: 96)
  }
}

/// A page's glass panel.
private struct SwitcherPanel<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) { content }
      .padding(28)
      .frame(width: OrbitLayout.panelWidth)
      .glassEffect(
        .regular,
        in: .rect(cornerRadius: OrbitLayout.panelCornerRadius, style: .continuous)
      )
      // Clicks inside the panel don't reach the background, which leaves.
      .contentShape(.rect(cornerRadius: OrbitLayout.panelCornerRadius))
      .onTapGesture {}
  }
}

private struct NewProfilePanel: View {
  @Bindable var model: ProfileSwitcherModel
  @FocusState private var isNameFocused: Bool

  private static let previewDiameter: CGFloat = 88
  private static let avatarDiameter: CGFloat = 40
  private static let avatarColumns = 6

  var body: some View {
    SwitcherPanel {
      preview
        .padding(.bottom, 16)
      Text("New Profile")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.bottom, 18)
      TextField("Name", text: $model.newProfileName)
        .textFieldStyle(.plain)
        .font(.system(size: 17))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.white.opacity(0.08), in: .capsule)
        .focused($isNameFocused)
        .onSubmit { model.create() }
        .padding(.bottom, 20)
      if !model.avatars.isEmpty {
        avatarGrid
          .padding(.bottom, 24)
      }
      HStack(spacing: 12) {
        Button {
          model.show(.orbit)
        } label: {
          KeyedButtonLabel(title: "Cancel", key: "esc")
        }
        .buttonStyle(.glass)
        Button {
          model.create()
        } label: {
          KeyedButtonLabel(title: "Create", key: "↩")
        }
        .buttonStyle(.glassProminent)
        .disabled(
          model.newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .controlSize(.extraLarge)
    }
    .onAppear { isNameFocused = true }
  }

  private var selectedAvatar: AvatarOption? {
    model.avatars.first { $0.id == model.newProfileAvatarID }
      ?? model.avatars.first
  }

  @ViewBuilder private var preview: some View {
    Group {
      if let avatar = selectedAvatar {
        Image(nsImage: avatar.image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "person.crop.circle.fill")
          .resizable()
          .foregroundStyle(.white.opacity(0.6))
      }
    }
    .frame(width: Self.previewDiameter, height: Self.previewDiameter)
    .clipShape(.circle)
    .contentTransition(.opacity)
    .animation(.easeOut(duration: 0.15), value: selectedAvatar?.id)
    .accessibilityHidden(true)
  }

  private var avatarGrid: some View {
    LazyVGrid(
      columns: Array(
        repeating: GridItem(.fixed(Self.avatarDiameter), spacing: 12),
        count: Self.avatarColumns),
      spacing: 12
    ) {
      ForEach(model.avatars) { avatar in
        let isChosen = avatar.id == selectedAvatar?.id
        Button {
          model.newProfileAvatarID = avatar.id
        } label: {
          Image(nsImage: avatar.image)
            .resizable()
            .scaledToFill()
            .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
            .clipShape(.circle)
            .overlay {
              Circle()
                .strokeBorder(.white, lineWidth: 2)
                .padding(-4)
                .opacity(isChosen ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(avatar.label)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
      }
    }
  }
}

private struct ImportPanel: View {
  @Bindable var model: ProfileSwitcherModel

  var body: some View {
    SwitcherPanel {
      if let icon = model.importIcon {
        Image(nsImage: icon)
          .resizable()
          .frame(width: 64, height: 64)
          .padding(.bottom, 14)
          .accessibilityHidden(true)
      }
      Text(model.importTitle)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.bottom, 6)
      Text("A new profile, with its bookmarks, history, passwords and cookies.")
        .font(.system(size: 14))
        .foregroundStyle(.white.opacity(0.75))
        .multilineTextAlignment(.center)
        .padding(.bottom, 20)

      switch model.importState {
      case .choosing, .failed:
        sources
          .padding(.bottom, 24)
        if case .failed(let message) = model.importState {
          Text(message)
            .font(.system(size: 13))
            .foregroundStyle(.red)
            .padding(.bottom, 16)
        }
        buttons
      case .importing(let step):
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text(step)
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.85))
        }
        .frame(height: 44)
      }
    }
  }

  private var sources: some View {
    VStack(spacing: 4) {
      ForEach(model.importSources) { source in
        let isChosen = source.id == model.importSourceID
        Button {
          model.importSourceID = source.id
        } label: {
          HStack(spacing: 12) {
            Group {
              if let avatar = source.avatar {
                Image(nsImage: avatar).resizable().scaledToFill()
              } else {
                Image(systemName: "person.crop.circle.fill").resizable()
              }
            }
            .frame(width: 32, height: 32)
            .clipShape(.circle)
            VStack(alignment: .leading, spacing: 1) {
              Text(source.name)
                .font(.system(size: 14, weight: .medium))
              if !source.detail.isEmpty {
                Text(source.detail)
                  .font(.system(size: 12))
                  .opacity(0.65)
              }
            }
            Spacer(minLength: 0)
            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
              .font(.system(size: 17))
              .foregroundStyle(isChosen ? Color.accentColor : .white.opacity(0.4))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .frame(height: 48)
          .background(
            .white.opacity(isChosen ? 0.12 : 0.04),
            in: .rect(cornerRadius: 14, style: .continuous)
          )
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
      }
    }
  }

  private var buttons: some View {
    HStack(spacing: 12) {
      Button {
        model.show(.orbit)
      } label: {
        KeyedButtonLabel(title: "Cancel", key: "esc")
      }
      .buttonStyle(.glass)
      Button {
        model.startImport()
      } label: {
        KeyedButtonLabel(title: "Import", key: "↩")
      }
      .buttonStyle(.glassProminent)
      .disabled(model.importSourceID == nil)
    }
    .controlSize(.extraLarge)
  }
}
