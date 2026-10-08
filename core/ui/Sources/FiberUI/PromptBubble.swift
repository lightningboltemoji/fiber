import AppKit
import FiberBridge
import SwiftUI

/// Something the browser asks in a PromptBubble: Chrome's words.
@MainActor
final class BubblePrompt: NSObject, FiberPrompt {
  private let actions: any FiberPromptActions
  private weak var controller: BrowserWindowController?
  private let bubble: PromptBubble
  private var isDone = false

  /// On tab `tabID`'s page, or, without one, the window's.
  init(
    content: FiberPromptContent, tabID: Int?, window: NSWindow,
    actions: any FiberPromptActions
  ) {
    self.actions = actions
    controller = BrowserWindowController.controller(for: window)
    bubble = PromptBubble(model: PromptBubbleModel(content: content))
    super.init()
    bubble.model.onButton = { [weak self] buttonID in
      self?.finish { $0.promptDidPressButton(withID: buttonID) }
    }
    bubble.model.onDismiss = { [weak self] in
      self?.finish { $0.promptDidDismiss() }
    }
    bubble.onRemoved = { [weak self] in
      self?.finish(removing: false) { $0.promptDidDismiss() }
    }
    guard let controller else {
      // Nowhere to ask; after returning, since the answer can end the
      // prompt's owner.
      DispatchQueue.main.async {
        self.finish { $0.promptDidDismiss() }
      }
      return
    }
    controller.present(bubble, forTabWithID: tabID)
  }

  var fieldValues: [String] { bubble.model.fieldValues }
  var checkboxChecked: Bool { bubble.model.isChecked }

  func close() {
    finish { $0.promptDidDismiss() }
  }

  /// Takes the bubble down, unless it's already gone, and reports how it
  /// ended, once.
  private func finish(
    removing: Bool = true, _ report: (any FiberPromptActions) -> Void
  ) {
    guard !isDone else {
      return
    }
    isDone = true
    if removing {
      controller?.dismiss(bubble)
    }
    report(actions)
  }
}

/// A question in glass over the page, which stays usable around it: a capsule,
/// or a rounded rectangle to fit more, opening from a circle around its icon
/// as a wave like the tab overlay's runs across it. Only its glass is clicked.
@MainActor
final class PromptBubble: NSView {
  /// Called if it goes without being answered or dismissed by its owner:
  /// another took its place, or its tab or window closed.
  var onRemoved: (() -> Void)?
  private(set) var isShown = false
  /// Set while the window looks at the page behind it, before it shows.
  var isMeasuringBackdrop = false

  let model: PromptBubbleModel
  /// Counts showings and hidings, so a step left from an earlier one does
  /// nothing.
  private var generation = 0

  /// Its glass is dark over a page darker than this, in L*, and light
  /// otherwise: light glass reads over anything, dark glass only over dark.
  private static let darkBackdropLightness = 50.0

  private enum Timing {
    /// How long it shows as a circle before it stretches open, and how long
    /// after that its confirm buttons can be pressed.
    static let stretchDelay: TimeInterval = 0.6
    static let armDelay: TimeInterval = 0.4
  }

  init(model: PromptBubbleModel) {
    self.model = model
    super.init(frame: .zero)
    let hostingView = NSHostingView(rootView: PromptBubbleView(model: model))
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    isHidden = true
  }

  /// Where it is once open, in units of the page's size, from its top-left
  /// corner.
  var openRegion: CGRect {
    let page = model.pageSize
    guard page.width > 0, page.height > 0 else {
      return .zero
    }
    let size = CGSize(
      width: max(model.contentSize.width, PromptBubbleModel.diameter),
      height: max(model.contentSize.height, PromptBubbleModel.diameter))
    let center = model.capsuleCenter
    return CGRect(
      x: (center.x - size.width / 2) / page.width,
      y: (center.y - size.height / 2) / page.height,
      width: size.width / page.width, height: size.height / page.height)
  }

  /// Makes its glass light or dark for how light what's behind it is (its
  /// L*), whatever the window's appearance.
  func setBackdropLightness(_ lightness: Double) {
    appearance = NSAppearance(
      named: lightness < Self.darkBackdropLightness ? .darkAqua : .aqua)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func layout() {
    super.layout()
    if model.pageSize != bounds.size {
      model.pageSize = bounds.size
    }
  }

  override var mouseDownCanMoveWindow: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let size = model.capsuleSize
    let center = model.capsuleCenter
    let capsule = NSRect(
      x: center.x - size.width / 2,
      y: bounds.height - center.y - size.height / 2, width: size.width,
      height: size.height)
    guard isShown, capsule.contains(convert(point, from: superview)) else {
      return nil
    }
    return super.hitTest(point)
  }

  // MARK: Keyboard

  /// Whether it, or one of its fields, has the keyboard.
  var hasKeyboard: Bool {
    (window?.firstResponder as? NSView)?.isDescendant(of: self) ?? false
  }

  /// Puts the keyboard in its first field, or, without one, in itself, for
  /// Return and Escape.
  func takeKeyboard() {
    // Its fields' views are made as SwiftUI lays it out.
    layoutSubtreeIfNeeded()
    window?.makeFirstResponder(Self.firstField(in: self) ?? self)
  }

  private static func firstField(in view: NSView) -> NSTextField? {
    fields(in: view).first
  }

  /// Its text fields, in order.
  private static func fields(in view: NSView) -> [NSTextField] {
    view.subviews.flatMap { subview in
      if let field = subview as? NSTextField, field.isEditable {
        [field]
      } else {
        fields(in: subview)
      }
    }
  }

  /// Tab and Shift-Tab, from one of its fields to the next, around.
  func moveKeyboard(from field: NSTextField, backward: Bool) {
    let fields = Self.fields(in: self)
    guard let index = fields.firstIndex(of: field) else {
      return
    }
    let next = (index + (backward ? -1 : 1) + fields.count) % fields.count
    window?.makeFirstResponder(fields[next])
  }

  /// Shows the keys that press its buttons while they work, once the
  /// keyboard has settled: Tab passes it through the window between fields.
  func firstResponderDidChange() {
    guard !isKeyboardUpdateScheduled else {
      return
    }
    isKeyboardUpdateScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else {
          return
        }
        self.isKeyboardUpdateScheduled = false
        let showsKeys = self.isShown && self.hasKeyboard
        guard showsKeys != self.model.hasKeyboard else {
          return
        }
        withAnimation(.smooth(duration: 0.2).slowMotion) {
          self.model.hasKeyboard = showsKeys
        }
      }
    }
  }

  private var isKeyboardUpdateScheduled = false

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76:  // Return, Enter
      model.pressDefaultButton()
    case 53:  // Escape
      model.pressEscape()
    case 48:  // Tab, to its buttons through the window
      super.keyDown(with: event)
    default:
      // Not the page's: it gets the keyboard back with a click.
      break
    }
  }

  // MARK: Showing

  /// Pops in and opens, from wherever it is.
  func show() {
    guard !isShown else {
      return
    }
    isShown = true
    generation += 1
    isHidden = false
    model.isArmed = false
    after(Timing.stretchDelay + Timing.armDelay) { $0.model.isArmed = true }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      withAnimation(.easeOut(duration: 0.2).slowMotion) {
        model.stage = .open
      }
      return
    }
    withAnimation(.spring(duration: 0.35, bounce: 0.4).slowMotion) {
      model.stage = .circle
    }
    after(Timing.stretchDelay) { bubble in
      withAnimation(.spring(duration: 0.55, bounce: 0.2).slowMotion) {
        bubble.model.stage = .open
      }
    }
  }

  /// Shrinks away while its tab isn't active, or the window's own prompt is
  /// up.
  func hide() {
    guard isShown else {
      return
    }
    isShown = false
    generation += 1
    let generation = generation
    model.hasKeyboard = false
    withAnimation(.easeIn(duration: 0.15).slowMotion) {
      model.stage = .hidden
    } completion: { [weak self] in
      guard let self, self.generation == generation else {
        return
      }
      self.isHidden = true
    }
  }

  /// Folds back into its icon's circle and shrinks away, then leaves its
  /// superview.
  func leave() {
    isShown = false
    generation += 1
    model.hasKeyboard = false
    let wasOpen = model.stage == .open
    if wasOpen {
      withAnimation(.spring(duration: 0.3, bounce: 0).slowMotion) {
        model.stage = .circle
      }
    }
    after(wasOpen ? 0.18 : 0) { bubble in
      withAnimation(.easeIn(duration: 0.15).slowMotion) {
        bubble.model.stage = .hidden
      } completion: {
        bubble.removeFromSuperview()
      }
    }
  }

  /// Runs `step` `delay` from now, unless it has shown or hidden since.
  private func after(
    _ delay: TimeInterval, _ step: @escaping (PromptBubble) -> Void
  ) {
    let generation = generation
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SlowMotion.duration(delay)
    ) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.generation == generation else {
          return
        }
        step(self)
      }
    }
  }
}

@MainActor
@Observable
final class PromptBubbleModel {
  enum Stage {
    case hidden, circle, open
  }

  /// The circle it opens from, which the icon stays in at its leading end.
  nonisolated static let diameter: CGFloat = 56
  static let rimWidth: CGFloat = 5
  /// A bubble up to twice this tall is a capsule; a taller one keeps these
  /// corners, and its icon and buttons stay in the first and last rows of
  /// that height.
  nonisolated static let maxCornerRadius: CGFloat = 36
  /// Kept clear between the bubble and the page's sides.
  static let margin: CGFloat = 24
  /// The bubble is in the middle of a page up to `centeredHeight` tall, and
  /// rises with a taller one, to `raisedPosition` of the way down from
  /// `raisedHeight`.
  static let centeredHeight: CGFloat = 500
  static let raisedHeight: CGFloat = 700
  static let raisedPosition: CGFloat = 1 / 4
  /// How fast the wave spreads, in points a second, its soft edge, and how
  /// much of the text and buttons show past its front.
  static let waveSpeed: CGFloat = 1000
  static let waveEdgeWidth: CGFloat = 160
  static let waveFloorOpacity = 0.3
  /// How long the wave takes to play back as the bubble folds, for each
  /// second it takes as it opens.
  static let waveCloseShare = 0.5

  var stage = Stage.hidden
  /// Its content as laid out in full, which the bubble opens to.
  var contentSize = CGSize.zero
  var pageSize = CGSize.zero
  /// Whether its confirm buttons can be pressed yet.
  var isArmed = false
  /// Whether it has the keyboard, so Return and Escape press its buttons.
  var hasKeyboard = false

  let icon: NSImage?
  let topic: FiberPromptTopic
  let eyebrow: String
  let title: String
  var message: String
  let listHeading: String
  let listItems: [FiberPromptListItem]
  let fields: [FiberPromptField]
  var fieldValues: [String]
  let checkboxTitle: String
  var isChecked = false
  let buttons: [FiberPromptButton]
  /// The button that's tinted: the last that's default or confirm.
  let prominentButtonID: Int?
  /// Under the rest of the text: a list that changes, say.
  @ObservationIgnored let accessory: AnyView?
  @ObservationIgnored var onButton: (Int) -> Void = { _ in }
  /// Escape, without a cancel button.
  @ObservationIgnored var onDismiss: () -> Void = {}

  init(
    icon: NSImage? = nil, topic: FiberPromptTopic, eyebrow: String = "",
    title: String, message: String = "", listHeading: String = "",
    listItems: [FiberPromptListItem] = [], fields: [FiberPromptField] = [],
    checkboxTitle: String = "", buttons: [FiberPromptButton],
    accessory: AnyView? = nil
  ) {
    self.icon = icon
    self.topic = topic
    self.eyebrow = eyebrow
    self.title = title
    self.message = message
    self.listHeading = listHeading
    self.listItems = listItems
    self.fields = fields
    fieldValues = fields.map(\.text)
    self.checkboxTitle = checkboxTitle
    self.buttons = buttons
    prominentButtonID =
      buttons.last { $0.role == .default || $0.role == .confirm }?.buttonID
    self.accessory = accessory
  }

  convenience init(content: FiberPromptContent) {
    self.init(
      icon: content.icon, topic: content.topic, eyebrow: content.eyebrow,
      title: content.title, message: content.message,
      listHeading: content.listHeading, listItems: content.listItems,
      fields: content.fields, checkboxTitle: content.checkboxTitle,
      buttons: content.buttons)
  }

  func pressDefaultButton() {
    if let button = buttons.first(where: { $0.role == .default }) {
      onButton(button.buttonID)
    }
  }

  /// Presses the cancel button, or, without one, dismisses the bubble.
  func pressEscape() {
    if let button = buttons.first(where: { $0.role == .cancel }) {
      onButton(button.buttonID)
    } else {
      onDismiss()
    }
  }

  /// Its first row's height, which its icon is in the middle of, and its
  /// last's, its buttons'.
  var rowHeight: CGFloat {
    min(max(contentSize.height, Self.diameter), 2 * Self.maxCornerRadius)
  }

  var capsuleSize: CGSize {
    let diameter = Self.diameter
    guard stage == .open else {
      return CGSize(width: diameter, height: diameter)
    }
    return CGSize(
      width: max(contentSize.width, diameter),
      height: max(contentSize.height, diameter))
  }

  var cornerRadius: CGFloat {
    min(capsuleSize.height / 2, Self.maxCornerRadius)
  }

  /// From the page's top-left corner. A tall bubble moves down from the top
  /// of the page, then up from its bottom, as far as it has to to fit.
  var capsuleCenter: CGPoint {
    let rise = min(
      max(
        (pageSize.height - Self.centeredHeight)
          / (Self.raisedHeight - Self.centeredHeight), 0), 1)
    let position = 0.5 + (Self.raisedPosition - 0.5) * rise
    let halfHeight = max(contentSize.height, Self.diameter) / 2
    let y = min(
      max(pageSize.height * position, Self.margin + halfHeight),
      max(pageSize.height - Self.margin - halfHeight, Self.margin + halfHeight))
    return CGPoint(x: pageSize.width / 2, y: y)
  }

  /// How far its content moves down, so that its icon is in the middle of
  /// the circle it opens from.
  var contentOffset: CGFloat {
    stage == .open ? 0 : (Self.diameter - rowHeight) / 2
  }

  /// How far a view `size`, beside the icon, reaches from the icon's center
  /// at its far corner.
  func waveReach(across size: CGSize) -> CGFloat {
    let iconCenterY = rowHeight / 2
    return hypot(
      size.width + Self.diameter / 2,
      max(iconCenterY, size.height - iconCenterY))
  }

  var waveAnimation: Animation {
    let reach = waveReach(
      across: CGSize(
        width: max(contentSize.width - Self.diameter, 0),
        height: contentSize.height))
    let duration = TimeInterval((reach + Self.waveEdgeWidth) / Self.waveSpeed)
    return .linear(
      duration: stage == .open ? duration : Self.waveCloseShare * duration
    ).slowMotion
  }
}

/// Draws a PromptBubble: the glass, and its content laid out whole and cut to
/// it, so the glass uncovers it as it opens.
struct PromptBubbleView: View {
  private static let sectionSpacing: CGFloat = 10
  /// Between the last button and the bubble's end.
  private static let endInset: CGFloat = 16
  private static let iconSize: CGFloat = 24

  @Bindable var model: PromptBubbleModel

  var body: some View {
    let size = model.capsuleSize
    let radius = model.cornerRadius
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    ZStack {
      PanelShadow(cornerRadius: radius)
      RimmedGlass(cornerRadius: radius, rimWidth: PromptBubbleModel.rimWidth)
        .accessibilityHidden(true)
      content
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
          // Growing or shrinking once open (a field's keys showing, a
          // download done), the glass follows.
          if model.stage == .open {
            withAnimation(.smooth(duration: 0.25).slowMotion) {
              model.contentSize = size
            }
          } else {
            model.contentSize = size
          }
        }
        .frame(
          width: max(
            model.pageSize.width - 2 * PromptBubbleModel.margin,
            PromptBubbleModel.diameter),
          alignment: .leading
        )
        .offset(y: model.contentOffset)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(shape)
    }
    .frame(width: size.width, height: size.height)
    .scaleEffect(model.stage == .hidden ? 0.4 : 1)
    .opacity(model.stage == .hidden ? 0 : 1)
    .position(model.capsuleCenter)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(model.title)
  }

  private var isOpen: Bool { model.stage == .open }

  private var content: some View {
    HStack(alignment: .top, spacing: 0) {
      PromptIcon(image: model.icon, topic: model.topic, size: Self.iconSize)
        .frame(
          width: PromptBubbleModel.diameter, height: PromptBubbleModel.diameter
        )
        .padding(
          .top, max((model.rowHeight - PromptBubbleModel.diameter) / 2, 0))
      PromptBodyLayout(fieldCount: model.fields.count) {
        details
          .layoutValue(key: PromptPart.self, value: .text)
        if !model.fields.isEmpty {
          VStack(spacing: PromptBodyLayout.fieldSpacing) {
            ForEach(model.fields.indices, id: \.self) { index in
              field(at: index)
            }
          }
          .layoutValue(key: PromptPart.self, value: .fields)
        }
        ForEach(model.buttons, id: \.buttonID) { button in
          bubbleButton(button)
            .disabled(button.role == .confirm && !model.isArmed)
            .layoutValue(key: PromptPart.self, value: .button)
        }
      }
      .controlSize(.large)
      .mask {
        GeometryReader { proxy in
          BubbleWave(
            progress: isOpen ? 1 : 0, size: proxy.size,
            reach: model.waveReach(across: proxy.size),
            iconCenterY: model.rowHeight / 2
          )
          .animation(model.waveAnimation, value: isOpen)
        }
      }
    }
    .padding(.trailing, Self.endInset)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: Self.sectionSpacing) {
      VStack(alignment: .leading, spacing: 1) {
        if !model.eyebrow.isEmpty {
          Text(model.eyebrow)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        Text(model.title)
          .font(.system(size: 13, weight: .semibold))
        if !model.message.isEmpty {
          Text(model.message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        // Under the title, without a heading: more of what's asked.
        if model.listHeading.isEmpty {
          list
        }
      }
      if !model.listHeading.isEmpty {
        VStack(alignment: .leading, spacing: 3) {
          Text(model.listHeading)
            .font(.system(size: 12, weight: .medium))
          list
        }
      }
      if !model.checkboxTitle.isEmpty {
        Toggle(isOn: $model.isChecked) {
          Text(model.checkboxTitle)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
      }
      if let accessory = model.accessory {
        accessory
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var list: some View {
    ForEach(Array(model.listItems.enumerated()), id: \.offset) { _, item in
      VStack(alignment: .leading, spacing: 1) {
        Text(item.text)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        if !item.detail.isEmpty {
          Text(item.detail)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
      }
    }
  }

  private func field(at index: Int) -> some View {
    PromptTextField(
      field: model.fields[index], text: $model.fieldValues[index],
      onSubmit: { model.pressDefaultButton() },
      onCancel: { model.pressEscape() }
    )
    .padding(.horizontal, 10)
    .frame(height: PromptBodyLayout.fieldHeight)
    .background(.primary.opacity(0.08), in: .capsule)
  }

  @ViewBuilder
  private func bubbleButton(_ button: FiberPromptButton) -> some View {
    let key: String? =
      switch button.role {
      case .default: "↩"
      case .cancel: "esc"
      default: nil
      }
    let label = Button {
      model.onButton(button.buttonID)
    } label: {
      HStack(spacing: 6) {
        Text(button.title)
        // The key that presses it, while it has the keyboard.
        if let key, model.hasKeyboard {
          Text(key)
            .font(.system(size: 11, weight: .medium))
            .opacity(0.55)
            .transition(.opacity)
        }
      }
      // As wide as the others when they're stacked.
      .frame(maxWidth: .infinity)
    }
    if button.buttonID == model.prominentButtonID {
      label.buttonStyle(.glassProminent)
    } else {
      label.buttonStyle(.glass)
    }
  }
}

/// A prompt's text field: AppKit's, which PromptBubble can give the keyboard
/// to, unlike SwiftUI's, which has no view until it's focused.
private struct PromptTextField: NSViewRepresentable {
  let field: FiberPromptField
  @Binding var text: String
  let onSubmit: () -> Void
  let onCancel: () -> Void

  func makeNSView(context: Context) -> NSTextField {
    let textField =
      field.kind == .password ? NSSecureTextField() : NSTextField()
    textField.stringValue = text
    textField.placeholderString = field.placeholder
    textField.isBordered = false
    textField.drawsBackground = false
    textField.focusRingType = .none
    textField.font = .systemFont(ofSize: 13)
    textField.cell?.isScrollable = true
    textField.cell?.wraps = false
    // Without a content type, AppKit's AutoFill guesses one, and offers
    // one-time codes in a list that flashes up under the field.
    textField.contentType =
      switch field.kind {
      case .username: .username
      case .password: .password
      default: .URL
      }
    textField.delegate = context.coordinator
    return textField
  }

  func updateNSView(_ textField: NSTextField, context: Context) {
    context.coordinator.parent = self
    if textField.stringValue != text {
      textField.stringValue = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: PromptTextField

    init(parent: PromptTextField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      if let textField = notification.object as? NSTextField {
        parent.text = textField.stringValue
      }
    }

    // The field editor takes these keys before the bubble sees them.
    func control(
      _ control: NSControl, textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      switch commandSelector {
      case #selector(NSResponder.insertNewline(_:)):
        parent.onSubmit()
      case #selector(NSResponder.cancelOperation(_:)):
        parent.onCancel()
      case #selector(NSResponder.insertTab(_:)),
        #selector(NSResponder.insertBacktab(_:)):
        guard let textField = control as? NSTextField else {
          return false
        }
        var view = control.superview
        while let ancestor = view, !(ancestor is PromptBubble) {
          view = ancestor.superview
        }
        (view as? PromptBubble)?.moveKeyboard(
          from: textField,
          backward: commandSelector == #selector(NSResponder.insertBacktab(_:)))
      default:
        return false
      }
      return true
    }
  }
}

/// A prompt's icon: its own image, or its topic's symbol.
struct PromptIcon: View {
  let image: NSImage?
  let topic: FiberPromptTopic
  let size: CGFloat

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
      } else {
        let (symbol, primary, secondary) = topic.symbol
        let image = Image(systemName: symbol)
          .resizable()
          .scaledToFit()
          .fontWeight(.semibold)
        if let secondary {
          image
            .symbolRenderingMode(.palette)
            .foregroundStyle(primary, secondary)
        } else {
          image.foregroundStyle(primary)
        }
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

extension FiberPromptTopic {
  /// Its symbol, and the colors of the symbol's layers.
  fileprivate var symbol: (String, Color, Color?) {
    switch self {
    case .location: ("location.fill", Color(nsColor: .systemBlue), nil)
    case .camera: ("video.fill", Color(nsColor: .systemGreen), nil)
    case .microphone: ("mic.fill", Color(nsColor: .systemOrange), nil)
    case .notifications: ("bell.badge.fill", Color(nsColor: .systemRed), nil)
    case .clipboard: ("list.clipboard.fill", Color(nsColor: .systemBrown), nil)
    case .files: ("folder.fill", Color(nsColor: .systemCyan), nil)
    case .downloads:
      ("arrow.down.circle.fill", Color(nsColor: .systemBlue), nil)
    case .openApp:
      ("arrow.up.forward.app.fill", .white, Color(nsColor: .systemIndigo))
    case .signIn: ("key.fill", Color(nsColor: .systemYellow), nil)
    case .leave:
      (
        "rectangle.portrait.and.arrow.right.fill",
        Color(nsColor: .systemOrange), nil
      )
    case .extension:
      ("puzzlepiece.extension.fill", Color(nsColor: .systemGray), nil)
    case .localNetwork: ("network", Color(nsColor: .systemTeal), nil)
    case .MIDI: ("pianokeys", Color(nsColor: .systemPurple), nil)
    case .windows:
      ("macwindow.on.rectangle", Color(nsColor: .systemBlue), nil)
    case .storageAccess:
      ("cylinder.split.1x2.fill", Color(nsColor: .systemIndigo), nil)
    case .keyboardLock: ("keyboard.fill", Color(nsColor: .systemGray), nil)
    case .pointerLock: ("cursorarrow.rays", Color(nsColor: .systemGray), nil)
    case .spatial: ("visionpro", Color(nsColor: .systemPurple), nil)
    case .restore:
      ("clock.arrow.circlepath", Color(nsColor: .systemBlue), nil)
    default: ("questionmark.circle.fill", Color(nsColor: .systemGray), nil)
    }
  }
}

/// The mask of the text and buttons beside the icon as the wave spreads
/// across them from the icon's center, as the tab overlay's does across its
/// panel: opaque behind the wave's soft edge, and dimmer past its front.
private struct BubbleWave: View, Animatable {
  /// From the wave not yet started to past the far corner.
  var progress: CGFloat
  /// The masked view's.
  let size: CGSize
  /// To the masked view's far corner.
  let reach: CGFloat
  /// From the masked view's top.
  let iconCenterY: CGFloat

  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    let edge = PromptBubbleModel.waveEdgeWidth
    let front = progress * (reach + edge)
    RadialGradient(
      colors: [
        .black, .black.opacity(PromptBubbleModel.waveFloorOpacity),
      ],
      // The icon's center, before the view's leading edge.
      center: UnitPoint(
        x: size.width > 0 ? -PromptBubbleModel.diameter / 2 / size.width : 0,
        y: size.height > 0 ? iconCenterY / size.height : 0.5),
      startRadius: max(front - edge, 0), endRadius: max(front, 1))
  }
}

/// What a view in a PromptBodyLayout is.
private enum PromptPart: LayoutValueKey {
  case text, fields, button

  static let defaultValue = PromptPart.text
}

/// A prompt's text, fields and buttons: the buttons at the end while the text
/// fits in a row of the bubble's, under it once it's taller, and beside the
/// fields, one to a field if there are as many, else in a row by the last.
private struct PromptBodyLayout: Layout {
  static let fieldHeight: CGFloat = 28
  static let fieldSpacing: CGFloat = 6
  /// The text is as wide as it needs to be, up to this, unless the buttons
  /// under it are wider.
  private static let textMaxWidth: CGFloat = 300
  /// Narrower than this beside the buttons, the text has them under it.
  private static let besideMinWidth: CGFloat = 160
  /// Taller than this, the text has its buttons under it: a few lines.
  private static let besideMaxTextHeight: CGFloat = 54
  private static let buttonSpacing: CGFloat = 8
  /// Between the text or fields and the buttons beside them.
  private static let besideSpacing: CGFloat = 18
  /// Between the text and what's under it.
  private static let fieldsSpacing: CGFloat = 10
  private static let belowSpacing: CGFloat = 14
  /// Over and under the text, while the buttons are beside it. A taller
  /// bubble has as much over its text as under its last row.
  private static let inset: CGFloat = 12
  /// The last row's height, the buttons in its middle, as the icon is in the
  /// first's: the bubble's height while it's a capsule.
  private static let rowHeight = 2 * PromptBubbleModel.maxCornerRadius

  let fieldCount: Int

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    arrange(subviews, width: proposal.width).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
    cache: inout ()
  ) {
    let frames = arrange(subviews, width: proposal.width ?? bounds.width).frames
    for (subview, frame) in zip(subviews, frames) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        proposal: ProposedViewSize(frame.size))
    }
  }

  /// Its size, and its subviews' frames, in order, at `width` or less.
  private func arrange(_ subviews: Subviews, width: CGFloat?)
    -> (size: CGSize, frames: [CGRect])
  {
    let available = width ?? .infinity
    var frames = Array(repeating: CGRect.zero, count: subviews.count)
    let text = subviews.indices.first { subviews[$0][PromptPart.self] == .text }
    let fields = subviews.indices.first {
      subviews[$0][PromptPart.self] == .fields
    }
    let buttons = subviews.indices.filter {
      subviews[$0][PromptPart.self] == .button
    }
    let buttonSizes = buttons.map { subviews[$0].sizeThatFits(.unspecified) }
    let buttonHeight = buttonSizes.map(\.height).max() ?? 0
    let rowWidth =
      buttonSizes.map(\.width).reduce(0, +)
      + Self.buttonSpacing * CGFloat(max(buttons.count - 1, 0))
    let spacing = buttons.isEmpty ? 0 : Self.besideSpacing

    func measure(_ index: Int?, width: CGFloat) -> CGSize {
      guard let index else {
        return .zero
      }
      return subviews[index].sizeThatFits(
        ProposedViewSize(width: max(width, 0), height: nil))
    }

    /// A row of the buttons, its top `y`, ending at `maxX`.
    func placeRow(maxX: CGFloat, y: CGFloat) {
      var x = maxX - rowWidth
      for (index, size) in zip(buttons, buttonSizes) {
        frames[index] = CGRect(origin: CGPoint(x: x, y: y), size: size)
        x += size.width + Self.buttonSpacing
      }
    }

    /// Under a last row of `height`, in the middle of the bubble's.
    func lastRowInset(_ height: CGFloat) -> CGFloat {
      (Self.rowHeight - height) / 2
    }

    /// The buttons in a row under what ends at `y`, at the end.
    func placeBelow(width: CGFloat, y: CGFloat) -> CGSize {
      let width = max(width, rowWidth)
      let rowY = y + Self.belowSpacing
      placeRow(maxX: width, y: rowY)
      return CGSize(
        width: width, height: rowY + buttonHeight + lastRowInset(buttonHeight))
    }

    if let fields {
      let isStacked = fieldCount > 1 && buttons.count == fieldCount
      let columnWidth = buttonSizes.map(\.width).max() ?? 0
      let buttonsWidth = isStacked ? columnWidth : rowWidth
      let besideWidth = min(
        Self.textMaxWidth, available - buttonsWidth - spacing)
      let isBeside = besideWidth >= Self.besideMinWidth
      let width = isBeside ? besideWidth : min(Self.textMaxWidth, available)
      let textSize = measure(text, width: width)
      let textY = lastRowInset(isBeside ? Self.fieldHeight : buttonHeight)
      if let text {
        frames[text] = CGRect(origin: CGPoint(x: 0, y: textY), size: textSize)
      }
      let fieldsY = textY + textSize.height + Self.fieldsSpacing
      let fieldsHeight =
        CGFloat(fieldCount) * Self.fieldHeight
        + CGFloat(max(fieldCount - 1, 0)) * Self.fieldSpacing
      frames[fields] = CGRect(
        x: 0, y: fieldsY, width: width, height: fieldsHeight)
      guard isBeside else {
        return (placeBelow(width: width, y: fieldsY + fieldsHeight), frames)
      }
      let buttonsX = width + spacing
      // The middle of field `row`.
      func rowMidY(_ row: Int) -> CGFloat {
        fieldsY + CGFloat(row) * (Self.fieldHeight + Self.fieldSpacing)
          + Self.fieldHeight / 2
      }
      if isStacked {
        for (row, (index, size)) in zip(buttons, buttonSizes).enumerated() {
          frames[index] = CGRect(
            x: buttonsX, y: rowMidY(row) - size.height / 2,
            width: columnWidth, height: size.height)
        }
      } else {
        placeRow(
          maxX: buttonsX + rowWidth,
          y: rowMidY(fieldCount - 1) - buttonHeight / 2)
      }
      return (
        CGSize(
          width: buttonsX + buttonsWidth,
          height: fieldsY + fieldsHeight + lastRowInset(Self.fieldHeight)),
        frames
      )
    }

    let besideWidth = min(Self.textMaxWidth, available - rowWidth - spacing)
    let besideSize = measure(text, width: besideWidth)
    if besideWidth >= Self.besideMinWidth,
      besideSize.height <= Self.besideMaxTextHeight
    {
      let height = max(
        besideSize.height + 2 * Self.inset, PromptBubbleModel.diameter)
      if let text {
        frames[text] = CGRect(
          origin: CGPoint(x: 0, y: (height - besideSize.height) / 2),
          size: besideSize)
      }
      let width = besideSize.width + spacing + rowWidth
      placeRow(maxX: width, y: (height - buttonHeight) / 2)
      return (CGSize(width: width, height: height), frames)
    }

    // Under buttons wider than the text, the text can be as wide.
    let textSize = measure(
      text, width: min(max(Self.textMaxWidth, rowWidth), available))
    let textY = lastRowInset(buttonHeight)
    if let text {
      frames[text] = CGRect(origin: CGPoint(x: 0, y: textY), size: textSize)
    }
    return (
      placeBelow(width: textSize.width, y: textY + textSize.height), frames
    )
  }
}
