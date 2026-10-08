import AppKit
import FiberBridge
import SwiftUI

/// The layout of the tab overlay's downloads: a capsule under its panel that
/// opens into a panel over the tabs, growing up and to the left from the
/// capsule's bottom-right corner, with the capsule as its footer.
enum DownloadsLayout {
  /// Between the tab overlay's panel and the capsule.
  static let spacing = GlassCapsule.spacing
  static let panelWidth: CGFloat = 360
  static let cornerRadius = TabListLayout.cornerRadius
  static let rimWidth = GlassCapsule.rimWidth
  static let footerHeight = GlassCapsule.height
  static let rowHeight: CGFloat = 52
  static let rowSpacing: CGFloat = 2
  static var rowStep: CGFloat { rowHeight + rowSpacing }
  static let contentInset = TabListLayout.contentInset
  /// Past this many, the list scrolls.
  static let maxVisibleRows = 6
  /// How close the open panel comes to the window's top and left edges.
  static let margin: CGFloat = 16

  /// In the capsule: its title, then its indicator (a ring, a warning, or a
  /// fan of file icons), against its right end.
  @MainActor static let titleFont = NSFont.monospacedDigitSystemFont(
    ofSize: 13, weight: .medium)
  static let titleInset: CGFloat = 14
  static let indicatorSpacing: CGFloat = 8
  static let indicatorInset: CGFloat = 9
  static let indicatorSize: CGFloat = 22
  /// Between the fanned icons' left edges.
  static let fanStep: CGFloat = 11

  static func indicatorWidth(_ indicator: DownloadsSummary.Indicator)
    -> CGFloat
  {
    guard case .files(let count) = indicator else {
      return indicatorSize
    }
    return indicatorSize + CGFloat(max(count - 1, 0)) * fanStep
  }

  @MainActor
  static func capsuleWidth(for summary: DownloadsSummary) -> CGFloat {
    let title = (summary.title as NSString).size(withAttributes: [
      .font: titleFont
    ]).width.rounded(.up)
    return titleInset + title + indicatorSpacing
      + indicatorWidth(summary.indicator) + indicatorInset
  }

  /// The list's height, for `rows` downloads.
  static func listHeight(rows: Int) -> CGFloat {
    2 * contentInset + CGFloat(max(rows, 1)) * rowStep - rowSpacing
  }

  /// The open panel over `capsule`, listing `rows` downloads, as tall as
  /// fits.
  static func panelFrame(capsule: CGRect, rows: Int) -> CGRect {
    let width = max(min(panelWidth, capsule.maxX - margin), capsule.width)
    let height = max(
      min(
        footerHeight + listHeight(rows: min(rows, maxVisibleRows)),
        capsule.maxY - margin),
      footerHeight)
    return CGRect(
      x: capsule.maxX - width, y: capsule.maxY - height, width: width,
      height: height)
  }
}

/// The window's downloads in the tab overlay: one piece of glass that sums
/// them up as a capsule and grows into a panel listing them, over the tabs.
/// This view keeps the model; DownloadsBubbleView draws and takes the clicks.
@MainActor
final class DownloadsBubble: NSView {
  private static let expandAnimation = Animation.spring(
    duration: 0.42, bounce: 0.22)
  private static let collapseAnimation = Animation.spring(
    duration: 0.3, bounce: 0)
  /// Downloads coming and going, and the capsule following the panel.
  private static let changeAnimation = Animation.spring(
    duration: 0.3, bounce: 0)
  /// How long the capsule shows its check once the last download in progress
  /// finishes, before its files.
  private static let finishedDuration: TimeInterval = 1.8

  var onAction: (DownloadAction) -> Void = { _ in }
  /// Called as the capsule comes, goes or changes width, inside that change's
  /// animation, for the overlay to lay it out again.
  var onResize: () -> Void = {}
  /// Called as the glass moves or changes shape, inside that change's
  /// animation, for the dimming pooled under it to follow.
  var onGlassChange: () -> Void = {}
  /// Only while the tab overlay it's in is open does a download finishing
  /// show its check, or anything animate.
  var isOverlayOpen = false {
    didSet { model.isVisible = isOverlayOpen }
  }

  private let model = DownloadsBubbleModel()
  private let hostingView: DownloadsHostingView
  /// Until when the capsule shows that the last download finished.
  private var finishedUntil: Date?
  private var pendingFinishedEnd: DispatchWorkItem?

  override init(frame: NSRect) {
    hostingView = DownloadsHostingView(
      rootView: DownloadsBubbleView(model: model))
    super.init(frame: frame)
    wantsLayer = true
    hostingView.sizingOptions = []
    // The model's coordinates are the view's, title bar included.
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    model.onAction = { [weak self] action in self?.onAction(action) }
    model.onToggle = { [weak self] in
      guard let self else {
        return
      }
      self.setExpanded(!self.model.isExpanded, animated: true)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isFlipped: Bool { true }

  /// Whether there are downloads to show.
  var isShown: Bool { model.summary != nil }
  var isExpanded: Bool { model.isExpanded }
  /// The capsule, or the open panel; empty with no downloads.
  var glassFrame: CGRect { isShown ? model.glassFrame : .zero }
  var glassCornerRadius: CGFloat { model.glassCornerRadius }
  /// For what the capsule says now; 0 with no downloads.
  var capsuleWidth: CGFloat {
    model.summary.map(DownloadsLayout.capsuleWidth(for:)) ?? 0
  }

  func setDownloads(_ downloads: [FiberDownloadState]) {
    if isOverlayOpen, Self.didFinishLast(from: model.downloads, to: downloads)
    {
      showFinished()
    }
    // Progress alone comes several times a second, and what shows it
    // animates itself; the text it changes would only blur.
    let animation =
      Self.shape(of: downloads) != Self.shape(of: model.downloads)
      ? Self.changeAnimation.slowMotion : nil
    withAnimation(animation) {
      model.downloads = downloads
      if downloads.isEmpty {
        model.isExpanded = false
      }
      updateSummary()
    }
  }

  /// What a change in animates: which downloads there are, in what order,
  /// and how each is.
  private static func shape(of downloads: [FiberDownloadState]) -> [String] {
    downloads.map { "\($0.downloadID) \($0.status.rawValue) \($0.paused)" }
  }

  /// Where the capsule goes, in the overlay; it grows from no width as it
  /// appears.
  func setCapsuleFrame(_ frame: CGRect, animated: Bool) {
    guard frame != model.capsuleFrame else {
      return
    }
    var transaction = Transaction(
      animation: animated ? Self.changeAnimation.slowMotion : nil)
    transaction.disablesAnimations = !animated
    withTransaction(transaction) {
      model.capsuleFrame = frame
      onGlassChange()
    }
  }

  /// Opens the capsule into the panel, or closes it back.
  func setExpanded(_ expanded: Bool, animated: Bool) {
    guard expanded != model.isExpanded, !expanded || isShown else {
      return
    }
    let reduceMotion = NSWorkspace.shared
      .accessibilityDisplayShouldReduceMotion
    var animation =
      reduceMotion
      ? .easeInOut(duration: 0.15)
      : expanded ? Self.expandAnimation : Self.collapseAnimation
    animation = animation.slowMotion
    var transaction = Transaction(animation: animated ? animation : nil)
    transaction.disablesAnimations = !animated
    withTransaction(transaction) {
      model.isExpanded = expanded
      model.hoveredID = nil
      onGlassChange()
    }
  }

  /// Only the glass takes the pointer.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden, glassFrame.contains(convert(point, from: superview))
    else {
      return nil
    }
    return super.hitTest(point)
  }

  // What lands on the glass but nothing on it stops here, rather than going
  // on to the tabs under it.
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {}
  override func rightMouseDown(with event: NSEvent) {}
  override func otherMouseDown(with event: NSEvent) {}

  private func updateSummary() {
    let summary = DownloadsSummary(
      downloads: model.downloads,
      justFinished: finishedUntil.map { $0 > Date() } ?? false)
    guard summary != model.summary else {
      return
    }
    let resizes =
      summary.map(DownloadsLayout.capsuleWidth(for:))
      != model.summary.map(DownloadsLayout.capsuleWidth(for:))
    model.summary = summary
    if resizes {
      onResize()
    }
    onGlassChange()
  }

  /// The capsule's ring fills and turns into a check for a moment.
  private func showFinished() {
    let duration = SlowMotion.duration(Self.finishedDuration)
    finishedUntil = Date(timeIntervalSinceNow: duration)
    pendingFinishedEnd?.cancel()
    let end = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self else {
          return
        }
        self.finishedUntil = nil
        withAnimation(Self.changeAnimation.slowMotion) {
          self.updateSummary()
        }
      }
    }
    pendingFinishedEnd = end
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: end)
  }

  /// Whether a download that was in progress has finished, and none are left
  /// in progress or waiting on review.
  private static func didFinishLast(
    from old: [FiberDownloadState], to new: [FiberDownloadState]
  ) -> Bool {
    guard new.allSatisfy(\.isInactive) else {
      return false
    }
    let wereInProgress = Set(
      old.filter { $0.status == .inProgress }.map(\.downloadID))
    return new.contains {
      $0.status == .complete && wereInProgress.contains($0.downloadID)
    }
  }
}

/// Takes the first click in an inactive window, as the rest of the overlay
/// does.
private final class DownloadsHostingView: NSHostingView<DownloadsBubbleView> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }
}

@MainActor
@Observable
final class DownloadsBubbleModel {
  /// In progress or waiting on review first, then the rest, newest first.
  var downloads: [FiberDownloadState] = []
  /// Nil with no downloads.
  var summary: DownloadsSummary?
  var isExpanded = false
  /// Whether the overlay is open; hidden, nothing animates.
  var isVisible = false
  /// In the overlay, y growing down.
  var capsuleFrame: CGRect = .zero
  var hoveredID: String?
  @ObservationIgnored var onAction: (DownloadAction) -> Void = { _ in }
  @ObservationIgnored var onToggle: () -> Void = {}

  var panelFrame: CGRect {
    DownloadsLayout.panelFrame(capsule: capsuleFrame, rows: downloads.count)
  }

  var glassFrame: CGRect { isExpanded ? panelFrame : capsuleFrame }

  var glassCornerRadius: CGFloat {
    isExpanded ? DownloadsLayout.cornerRadius : capsuleFrame.height / 2
  }

  /// Whether any can come off the list.
  var canClear: Bool { downloads.contains(where: \.isInactive) }
}

/// Draws the downloads' glass where the model has it: the capsule, or the
/// open panel, with the list laid out where the open panel is and cut to the
/// glass, so the glass uncovers it as it grows.
struct DownloadsBubbleView: View {
  let model: DownloadsBubbleModel

  var body: some View {
    ZStack(alignment: .topLeading) {
      if let summary = model.summary {
        DownloadsGlass(model: model, summary: summary)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct DownloadsGlass: View {
  let model: DownloadsBubbleModel
  let summary: DownloadsSummary

  var body: some View {
    let panel = model.panelFrame
    let glass = model.glassFrame
    let cornerRadius = model.glassCornerRadius
    let footer = DownloadsLayout.footerHeight
    ZStack(alignment: .topLeading) {
      PanelShadow(cornerRadius: cornerRadius)
        .opacity(model.isExpanded ? 1 : 0)
        .frame(width: glass.width, height: glass.height)
        .offset(x: glass.minX, y: glass.minY)

      RimmedGlass(
        cornerRadius: cornerRadius, rimWidth: DownloadsLayout.rimWidth)
        .frame(width: glass.width, height: glass.height)
        .offset(x: glass.minX, y: glass.minY)
        .accessibilityHidden(true)

      DownloadList(model: model)
        .frame(width: panel.width, height: max(panel.height - footer, 0))
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, DownloadsLayout.contentInset + 6)
        }
        .mask(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .frame(width: glass.width, height: glass.height)
            .offset(x: glass.minX - panel.minX, y: glass.minY - panel.minY)
        }
        .opacity(model.isExpanded ? 1 : 0)
        .allowsHitTesting(model.isExpanded)
        .accessibilityHidden(!model.isExpanded)
        .offset(x: panel.minX, y: panel.minY)

      DownloadsFooter(model: model, summary: summary)
        .frame(width: glass.width, height: footer)
        .offset(x: glass.minX, y: glass.maxY - footer)
    }
  }
}

/// The capsule's summary, at the glass's bottom-right, and the open panel's
/// buttons at its bottom-left.
private struct DownloadsFooter: View {
  let model: DownloadsBubbleModel
  let summary: DownloadsSummary

  var body: some View {
    ZStack(alignment: .trailing) {
      HStack(spacing: 2) {
        FooterButton(title: "Show All") { model.onAction(.showAll) }
        if model.canClear {
          FooterButton(title: "Clear") { model.onAction(.clear) }
            .transition(.opacity)
        }
      }
      .padding(.leading, DownloadsLayout.rimWidth + 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .opacity(model.isExpanded ? 1 : 0)
      .allowsHitTesting(model.isExpanded)
      .accessibilityHidden(!model.isExpanded)

      SummaryButton(model: model, summary: summary)
        .frame(
          width: DownloadsLayout.capsuleWidth(for: summary),
          height: DownloadsLayout.footerHeight)
    }
  }
}

/// Opens the list, or closes it.
private struct SummaryButton: View {
  let model: DownloadsBubbleModel
  let summary: DownloadsSummary
  @State private var isHovered = false

  var body: some View {
    Button {
      model.onToggle()
    } label: {
      HStack(spacing: DownloadsLayout.indicatorSpacing) {
        Text(summary.title)
          .font(Font(DownloadsLayout.titleFont as CTFont))
          .lineLimit(1)
          .fixedSize()
          .contentTransition(.numericText(value: Double(summary.count)))
        SummaryIndicator(
          indicator: summary.indicator, downloads: model.downloads,
          isSpread: isHovered && !model.isExpanded, isAnimating: model.isVisible
        )
        .frame(
          width: DownloadsLayout.indicatorWidth(summary.indicator),
          height: DownloadsLayout.indicatorSize)
      }
      .padding(.leading, DownloadsLayout.titleInset)
      .padding(.trailing, DownloadsLayout.indicatorInset)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
      .background {
        Capsule()
          .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
          .padding(DownloadsLayout.rimWidth)
      }
      .contentShape(Capsule())
    }
    .buttonStyle(PressStyle())
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.15).slowMotion, value: isHovered)
    .accessibilityLabel("Downloads")
    .accessibilityValue(summary.title)
    .accessibilityAddTraits(model.isExpanded ? .isSelected : [])
  }
}

/// Gives a little as it's pressed.
private struct PressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(
        .spring(duration: 0.25, bounce: 0.45).slowMotion,
        value: configuration.isPressed)
  }
}

private struct SummaryIndicator: View {
  let indicator: DownloadsSummary.Indicator
  let downloads: [FiberDownloadState]
  let isSpread: Bool
  let isAnimating: Bool

  var body: some View {
    switch indicator {
    case .review:
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 15))
        .foregroundStyle(Color(nsColor: .systemOrange))
        .symbolEffect(
          .wiggle, options: .repeat(.periodic(delay: 2.5)),
          isActive: isAnimating)
        .accessibilityHidden(true)
    case .files(let count):
      FileFan(downloads: Array(downloads.prefix(count)), isSpread: isSpread)
    default:
      DownloadRing(indicator: indicator, isAnimating: isAnimating)
    }
  }
}

/// How far along the downloads in progress are, around an arrow that turns
/// into a check once they're done.
private struct DownloadRing: View {
  private static let lineWidth: CGFloat = 2.5

  let indicator: DownloadsSummary.Indicator
  let isAnimating: Bool

  var body: some View {
    let (progress, symbol, tint) = appearance
    ZStack {
      Circle()
        .stroke(Color.primary.opacity(0.14), lineWidth: Self.lineWidth)
      if let progress {
        Circle()
          .trim(from: 0, to: max(progress, 0.03))
          .stroke(
            tint,
            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
          .animation(.smooth(duration: 0.4).slowMotion, value: progress)
      } else {
        SpinningArc(
          tint: tint, lineWidth: Self.lineWidth, isAnimating: isAnimating)
      }
      Image(systemName: symbol)
        .font(.system(size: 9, weight: .heavy))
        .foregroundStyle(indicator == .finished ? tint : Color.secondary)
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(
          .wiggle.down, options: .repeat(.periodic(delay: 1.6)),
          isActive: isDownloading && isAnimating)
        .symbolEffect(.bounce, value: indicator == .finished)
    }
    .padding(Self.lineWidth / 2)
    .animation(.smooth(duration: 0.3).slowMotion, value: symbol)
    .accessibilityHidden(true)
  }

  private var isDownloading: Bool {
    if case .progress = indicator {
      return true
    }
    return false
  }

  private var appearance: (Double?, String, Color) {
    switch indicator {
    case .progress(let progress): (progress, "arrow.down", .accentColor)
    case .paused(let progress): (progress ?? 0, "pause.fill", .secondary)
    case .finished: (1, "checkmark", Color(nsColor: .systemGreen))
    default: (0, "arrow.down", .accentColor)
    }
  }
}

/// A quarter of a ring going round, for downloads of no known size.
private struct SpinningArc: View {
  private static let period: TimeInterval = 1.1

  let tint: Color
  let lineWidth: CGFloat
  let isAnimating: Bool

  var body: some View {
    TimelineView(.animation(paused: !isAnimating)) { context in
      let turns =
        context.date.timeIntervalSinceReferenceDate
        / (Self.period * SlowMotion.factor)
      Circle()
        .trim(from: 0, to: 0.28)
        .stroke(
          tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(
          .degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
    }
  }
}

/// The newest files' icons, fanned out like cards, the newest in front at
/// the right. They spread further under the pointer.
private struct FileFan: View {
  let downloads: [FiberDownloadState]
  let isSpread: Bool

  var body: some View {
    let count = downloads.count
    ZStack(alignment: .topLeading) {
      ForEach(
        Array(downloads.enumerated().reversed()), id: \.element.downloadID
      ) { index, download in
        let depth = CGFloat(index)
        Image(nsImage: DownloadFileIcon.image(for: download))
          .resizable()
          .interpolation(.high)
          .frame(
            width: DownloadsLayout.indicatorSize,
            height: DownloadsLayout.indicatorSize
          )
          .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
          .rotationEffect(
            .degrees(-depth * (isSpread ? 13 : 7)), anchor: .bottom)
          .offset(
            x: CGFloat(count - 1 - index) * DownloadsLayout.fanStep,
            y: isSpread && index == 0 ? -2 : 0)
      }
    }
    .frame(
      width: DownloadsLayout.indicatorWidth(.files(count: count)),
      height: DownloadsLayout.indicatorSize, alignment: .topLeading
    )
    .animation(.spring(duration: 0.35, bounce: 0.4).slowMotion, value: isSpread)
    .accessibilityHidden(true)
  }
}

/// The open panel's list, scrolling past a few, with a highlight that glides
/// to the row under the pointer. Its rows rise into place as it opens, the
/// nearest the capsule first.
private struct DownloadList: View {
  let model: DownloadsBubbleModel

  var body: some View {
    let visible = min(model.downloads.count, DownloadsLayout.maxVisibleRows)
    ScrollView {
      LazyVStack(spacing: DownloadsLayout.rowSpacing) {
        ForEach(
          Array(model.downloads.enumerated()), id: \.element.downloadID
        ) { index, download in
          DownloadRow(
            download: download,
            isHovered: model.hoveredID == download.downloadID,
            isAnimating: model.isVisible && model.isExpanded,
            onAction: model.onAction
          )
          .frame(height: DownloadsLayout.rowHeight)
          .onHover { isHovering in
            if isHovering {
              model.hoveredID = download.downloadID
            } else if model.hoveredID == download.downloadID {
              model.hoveredID = nil
            }
          }
          .opacity(model.isExpanded ? 1 : 0)
          .offset(y: model.isExpanded ? 0 : 10)
          .animation(
            rise(row: index, visible: visible), value: model.isExpanded)
          .transition(
            .asymmetric(
              insertion: .move(edge: .top).combined(with: .opacity),
              removal: .opacity))
        }
      }
      .padding(DownloadsLayout.contentInset)
      .background(alignment: .topLeading) { highlight }
    }
    .scrollIndicators(.automatic)
    .scrollBounceBehavior(.basedOnSize)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Downloads")
  }

  private func rise(row: Int, visible: Int) -> Animation {
    guard model.isExpanded else {
      return .easeOut(duration: 0.12).slowMotion
    }
    let delay = row < visible ? Double(visible - 1 - row) * 0.035 : 0
    return .spring(duration: 0.45, bounce: 0.25).delay(delay).slowMotion
  }

  @ViewBuilder private var highlight: some View {
    if let row = model.downloads.firstIndex(where: {
      $0.downloadID == model.hoveredID
    }) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.08))
        .frame(height: DownloadsLayout.rowHeight)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DownloadsLayout.contentInset)
        .offset(
          y: DownloadsLayout.contentInset + CGFloat(row)
            * DownloadsLayout.rowStep
        )
        .animation(.spring(duration: 0.22, bounce: 0.15).slowMotion, value: row)
        .transition(.opacity.animation(.easeOut(duration: 0.15)))
    }
  }
}

/// A download: its file's icon, name and how it's going, with buttons for
/// what can be done with it. Clicking a finished one opens it, and it can be
/// dragged out, as the file.
private struct DownloadRow: View {
  private static let buttonsFade = Animation.easeInOut(duration: 0.2)
  /// How far ahead of the buttons the text fades out.
  private static let textFadeWidth: CGFloat = 16
  private static let horizontalInset: CGFloat = 10

  let download: FiberDownloadState
  let isHovered: Bool
  let isAnimating: Bool
  let onAction: (DownloadAction) -> Void

  var body: some View {
    ZStack {
      // Takes the row's clicks, drags and right-clicks; what's on it is
      // only drawn.
      RowHitArea(download: download, onAction: onAction)

      HStack(spacing: 10) {
        DownloadIcon(download: download)
          .allowsHitTesting(false)
        text
          .mask { textMask }
          .allowsHitTesting(false)
        if showsButtonsAlways {
          buttons
        }
      }
      .padding(.horizontal, Self.horizontalInset)
      .overlay(alignment: .trailing) {
        if !showsButtonsAlways {
          buttons
            .padding(.trailing, Self.horizontalInset)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
      }
    }
    .animation(Self.buttonsFade.slowMotion, value: isHovered)
    .animation(.smooth(duration: 0.35).slowMotion, value: download.status)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(download.fileName)
    .accessibilityValue(DownloadText.subtitle(for: download))
    .accessibilityAddTraits(download.canOpen ? .isButton : [])
    .accessibilityActions { accessibilityActions }
  }

  private var text: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(download.fileName)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isDim ? .secondary : .primary)
        .lineLimit(1)
        .truncationMode(.middle)
      if download.status == .inProgress {
        DownloadProgressBar(
          progress: download.progress, isPaused: download.paused,
          isAnimating: isAnimating
        )
        .transition(
          .opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
      }
      Text(DownloadText.subtitle(for: download))
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(
          download.status == .needsReview
            ? AnyShapeStyle(Color(nsColor: .systemOrange))
            : AnyShapeStyle(.secondary)
        )
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Clear where the buttons show over the text.
  @ViewBuilder private var textMask: some View {
    if showsButtonsAlways {
      Rectangle()
    } else {
      HStack(spacing: 0) {
        Rectangle()
        LinearGradient(
          colors: [.black, .clear], startPoint: .leading, endPoint: .trailing
        )
        .frame(width: Self.textFadeWidth)
        Color.clear.frame(width: hoverButtonsWidth)
      }
      .overlay {
        Rectangle().opacity(isHovered ? 0 : 1)
      }
    }
  }

  /// Faded: it didn't finish, or its file's gone.
  private var isDim: Bool {
    download.status == .cancelled || download.status == .failed
      || download.fileMissing
  }

  /// In progress and needing review, they're what the row is for.
  private var showsButtonsAlways: Bool {
    download.status == .inProgress || download.status == .needsReview
  }

  private var hoverButtonsWidth: CGFloat {
    let count: CGFloat =
      download.status == .complete || retry == nil ? 1 : 2
    return count * RowButton.size + (count - 1) * 4
  }

  /// For one that failed or was cancelled: picking up where it left off, or
  /// starting again, if either can be done.
  private var retry: (label: String, action: DownloadAction)? {
    let id = download.downloadID
    if download.canResume {
      return ("Resume", .resume(id))
    }
    return download.canRetry ? ("Retry", .retry(id)) : nil
  }

  @ViewBuilder private var buttons: some View {
    let id = download.downloadID
    HStack(spacing: 4) {
      switch download.status {
      case .inProgress:
        RowButton(
          symbol: download.paused ? "play.fill" : "pause.fill",
          label: download.paused ? "Resume" : "Pause"
        ) {
          onAction(download.paused ? .resume(id) : .pause(id))
        }
        RowButton(symbol: "xmark", label: "Cancel") { onAction(.cancel(id)) }
      case .needsReview:
        Button("Delete") { onAction(.discard(id)) }
          .buttonStyle(.glassProminent)
          .tint(Color(nsColor: .systemRed))
        if download.canKeep {
          Button("Keep") { onAction(.keep(id)) }
            .buttonStyle(.glass)
        }
      case .complete:
        if download.canOpen {
          RowButton(symbol: "magnifyingglass", label: "Show in Finder") {
            onAction(.showInFinder(id))
          }
        } else {
          RowButton(symbol: "xmark", label: "Remove from List") {
            onAction(.remove(id))
          }
        }
      default:
        if let retry {
          RowButton(symbol: "arrow.clockwise", label: retry.label) {
            onAction(retry.action)
          }
        }
        RowButton(symbol: "xmark", label: "Remove from List") {
          onAction(.remove(id))
        }
      }
    }
    .controlSize(.small)
  }

  @ViewBuilder private var accessibilityActions: some View {
    let id = download.downloadID
    switch download.status {
    case .inProgress:
      Button(download.paused ? "Resume" : "Pause") {
        onAction(download.paused ? .resume(id) : .pause(id))
      }
      Button("Cancel") { onAction(.cancel(id)) }
    case .needsReview:
      Button("Delete") { onAction(.discard(id)) }
      if download.canKeep {
        Button("Keep") { onAction(.keep(id)) }
      }
    case .complete:
      if download.canOpen {
        Button("Open") { onAction(.open(id)) }
        Button("Show in Finder") { onAction(.showInFinder(id)) }
      }
      Button("Remove from List") { onAction(.remove(id)) }
    default:
      if let retry {
        Button(retry.label) { onAction(retry.action) }
      }
      Button("Remove from List") { onAction(.remove(id)) }
    }
  }
}

/// The row's own clicks: a finished file opens, drags out as itself, and
/// has a menu, as does every row.
private struct RowHitArea: View {
  let download: FiberDownloadState
  let onAction: (DownloadAction) -> Void

  var body: some View {
    let id = download.downloadID
    let shape = Color.clear.contentShape(Rectangle())
    Group {
      if download.canOpen, let url = download.fileURL {
        shape
          .onTapGesture { onAction(.open(id)) }
          .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
      } else {
        shape
      }
    }
    .help(
      download.status == .needsReview ? download.warningText : download.fileName
    )
    .contextMenu {
      switch download.status {
      case .inProgress:
        Button(download.paused ? "Resume" : "Pause") {
          onAction(download.paused ? .resume(id) : .pause(id))
        }
        Button("Cancel") { onAction(.cancel(id)) }
      case .needsReview:
        if download.canKeep {
          Button("Keep") { onAction(.keep(id)) }
        }
        Button("Delete") { onAction(.discard(id)) }
      case .complete:
        if download.canOpen {
          Button("Open") { onAction(.open(id)) }
          Button("Show in Finder") { onAction(.showInFinder(id)) }
          Divider()
        }
        Button("Remove from List") { onAction(.remove(id)) }
      default:
        if download.canResume {
          Button("Resume") { onAction(.resume(id)) }
        } else if download.canRetry {
          Button("Retry") { onAction(.retry(id)) }
        }
        Button("Remove from List") { onAction(.remove(id)) }
      }
    }
  }
}

/// The file's icon, with a badge for trouble. It pops as the file finishes.
private struct DownloadIcon: View {
  private static let size: CGFloat = 32

  let download: FiberDownloadState

  var body: some View {
    Image(nsImage: DownloadFileIcon.image(for: download))
      .resizable()
      .interpolation(.high)
      .frame(width: Self.size, height: Self.size)
      .opacity(download.isInactive && !download.canOpen ? 0.55 : 1)
      .overlay(alignment: .bottomTrailing) { badge }
      .keyframeAnimator(
        initialValue: 1.0, trigger: download.status == .complete
      ) { content, scale in
        content.scaleEffect(scale)
      } keyframes: { _ in
        SpringKeyframe(1.22, duration: 0.16, spring: .snappy)
        SpringKeyframe(1, duration: 0.45, spring: .bouncy)
      }
      .accessibilityHidden(true)
  }

  @ViewBuilder private var badge: some View {
    switch download.status {
    case .needsReview:
      badge("exclamationmark.triangle.fill", color: .systemOrange)
    case .failed:
      badge("exclamationmark.circle.fill", color: .systemRed)
    default:
      EmptyView()
    }
  }

  private func badge(_ symbol: String, color: NSColor) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 13, weight: .semibold))
      .symbolRenderingMode(.palette)
      .foregroundStyle(.white, Color(nsColor: color))
      .offset(x: 3, y: 3)
  }
}

/// How far along a download in progress is: a slim bar, or a segment
/// sweeping across while its size isn't known.
private struct DownloadProgressBar: View {
  private static let height: CGFloat = 4
  private static let sweepPeriod: TimeInterval = 1.4

  let progress: Double
  let isPaused: Bool
  let isAnimating: Bool

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ZStack(alignment: .leading) {
        Capsule().fill(Color.primary.opacity(0.1))
        if progress >= 0 {
          Capsule()
            .fill(fill)
            .frame(width: max(width * min(progress, 1), Self.height))
            .animation(.smooth(duration: 0.4).slowMotion, value: progress)
        } else if isPaused {
          Capsule().fill(fill).frame(width: width * 0.3)
        } else {
          TimelineView(.animation(paused: !isAnimating)) { context in
            let phase =
              (context.date.timeIntervalSinceReferenceDate
                / (Self.sweepPeriod * SlowMotion.factor))
              .truncatingRemainder(dividingBy: 1)
            Capsule()
              .fill(fill)
              .frame(width: width * 0.3)
              .offset(x: width * 1.3 * phase - width * 0.3)
          }
        }
      }
      .clipShape(Capsule())
    }
    .frame(height: Self.height)
    .animation(.easeInOut(duration: 0.25).slowMotion, value: isPaused)
  }

  private var fill: AnyShapeStyle {
    isPaused ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint)
  }
}

/// A round button on a row.
private struct RowButton: View {
  static let size: CGFloat = 24

  let symbol: String
  let label: String
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(isHovered ? .primary : .secondary)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: Self.size, height: Self.size)
        .background {
          Circle().fill(Color.primary.opacity(isHovered ? 0.14 : 0.07))
        }
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.15).slowMotion, value: isHovered)
    .animation(.snappy.slowMotion, value: symbol)
    .help(label)
    .accessibilityLabel(label)
  }
}

/// A text button in the open panel's footer.
private struct FooterButton: View {
  let title: String
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isHovered ? .primary : .secondary)
        .padding(.horizontal, 10)
        .frame(height: GlassCapsule.buttonSize)
        .background {
          Capsule().fill(Color.primary.opacity(isHovered ? 0.1 : 0))
        }
        .contentShape(Capsule())
    }
    .buttonStyle(PressStyle())
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.15).slowMotion, value: isHovered)
  }
}
