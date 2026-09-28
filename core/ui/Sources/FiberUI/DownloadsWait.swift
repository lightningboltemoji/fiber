import AppKit
import FiberBridge

@objc @implementation extension FiberDownloadState {
  let downloadID: String
  let fileName: String
  let statusText: String
  let progress: Double
  let paused: Bool

  init(
    downloadID: String, fileName: String, statusText: String,
    progress: Double, paused: Bool
  ) {
    self.downloadID = downloadID
    self.fileName = fileName
    self.statusText = statusText
    self.progress = progress
    self.paused = paused
    super.init()
  }
}

@objc @implementation extension FiberDownloadsWaitFactory {
  @objc(waitWithReason:window:actions:)
  class func wait(
    with reason: FiberDownloadsWaitReason, window: NSWindow,
    actions: any FiberDownloadsWaitActions
  ) -> any FiberDownloadsWait {
    DownloadsWait(reason: reason, window: window, actions: actions)
  }
}

/// A quit, or a window's close, waiting for downloads to finish, over the
/// veiled page: each download's progress, Continue Browsing to stop waiting,
/// and Quit (or Close) Now to go ahead without them.
@MainActor
final class DownloadsWait: NSObject, FiberDownloadsWait {
  private let actions: any FiberDownloadsWaitActions
  private weak var controller: BrowserWindowController?
  private let list = DownloadList()
  private var prompt: VeilPrompt?
  private var isClosed = false

  init(
    reason: FiberDownloadsWaitReason, window: NSWindow,
    actions: any FiberDownloadsWaitActions
  ) {
    self.actions = actions
    controller = BrowserWindowController.controller(for: window)
    super.init()

    let isQuit = reason == .quit
    list.onCancel = { [weak self] id in
      self?.actions.cancelDownload(withID: id)
    }
    list.onResume = { [weak self] id in
      self?.actions.resumeDownload(withID: id)
    }
    let prompt = VeilPrompt(
      title: isQuit
        ? "Quitting when downloads finish" : "Closing when downloads finish",
      message: "", accessory: list,
      buttons: [
        .init(title: "Continue Browsing", role: .cancel) { [weak self] in
          self?.finish { $0.stopWaiting() }
        },
        .init(title: isQuit ? "Quit Now" : "Close Now", role: .other) {
          [weak self] in self?.finish { $0.proceedNow() }
        },
      ])
    self.prompt = prompt
    guard let controller else {
      // Nowhere to wait, so don't.
      DispatchQueue.main.async {
        self.finish { $0.stopWaiting() }
      }
      return
    }
    controller.present(prompt)
  }

  func setDownloads(_ downloads: [FiberDownloadState]) {
    list.setDownloads(downloads)
    prompt?.message =
      downloads.count == 1 ? "1 download left" : "\(downloads.count) downloads left"
  }

  func close() {
    guard !isClosed else {
      return
    }
    isClosed = true
    if let prompt {
      controller?.dismiss(prompt)
    }
  }

  /// Takes the wait down and reports what the user chose, once.
  private func finish(_ report: (any FiberDownloadsWaitActions) -> Void) {
    guard !isClosed else {
      return
    }
    close()
    report(actions)
  }
}

/// The downloads being waited for, a row each, scrolling past a few.
@MainActor
private final class DownloadList: NSView {
  static let width: CGFloat = 440
  private static let maxVisibleRows = 5
  private static let rowSpacing: CGFloat = 6

  var onCancel: (String) -> Void = { _ in }
  var onResume: (String) -> Void = { _ in }

  private let scrollView = NSScrollView()
  private let rowsView = FlippedView()
  private var rows: [String: DownloadRow] = [:]
  private var order: [String] = []
  private lazy var heightConstraint = heightAnchor.constraint(
    equalToConstant: 0)

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.documentView = rowsView
    scrollView.autoresizingMask = [.width, .height]
    addSubview(scrollView)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Self.width), heightConstraint,
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Rows stay with their downloads, so progress animates from where it was.
  func setDownloads(_ downloads: [FiberDownloadState]) {
    let ids = Set(downloads.map(\.downloadID))
    for (id, row) in rows where !ids.contains(id) {
      row.removeFromSuperview()
      rows[id] = nil
    }
    order = downloads.map(\.downloadID)
    for download in downloads {
      let row =
        rows[download.downloadID]
        ?? {
          let row = DownloadRow()
          row.onCancel = { [weak self] in self?.onCancel(download.downloadID) }
          row.onResume = { [weak self] in self?.onResume(download.downloadID) }
          rows[download.downloadID] = row
          rowsView.addSubview(row)
          return row
        }()
      row.set(download)
    }
    layoutRows()
  }

  private func layoutRows() {
    let pitch = DownloadRow.height + Self.rowSpacing
    for (index, id) in order.enumerated() {
      rows[id]?.frame = NSRect(
        x: 0, y: CGFloat(index) * pitch, width: Self.width,
        height: DownloadRow.height)
    }
    let contentHeight = max(CGFloat(order.count) * pitch - Self.rowSpacing, 0)
    rowsView.frame = NSRect(
      x: 0, y: 0, width: Self.width, height: contentHeight)
    let visibleRows = min(order.count, Self.maxVisibleRows)
    heightConstraint.constant = max(
      CGFloat(visibleRows) * pitch - Self.rowSpacing, 0)
    scrollView.frame = NSRect(
      x: 0, y: 0, width: Self.width, height: heightConstraint.constant)
  }
}

@MainActor
private final class DownloadRow: FlippedView {
  static let height: CGFloat = 50
  private static let buttonSize: CGFloat = 28
  private static let buttonSpacing: CGFloat = 8
  private static let textInset: CGFloat = 14

  var onCancel: () -> Void = {}
  var onResume: () -> Void = {}

  private let nameLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private let progressBar = ProgressBar()
  private let resumeButton = DownloadRow.makeButton(
    symbol: "play.fill", label: "Resume")
  private let cancelButton = DownloadRow.makeButton(
    symbol: "xmark", label: "Cancel")

  init() {
    super.init(frame: .zero)
    nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
    nameLabel.textColor = .white
    nameLabel.lineBreakMode = .byTruncatingMiddle
    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = .white.withAlphaComponent(0.65)
    statusLabel.lineBreakMode = .byTruncatingTail
    resumeButton.target = self
    resumeButton.action = #selector(resume(_:))
    cancelButton.target = self
    cancelButton.action = #selector(cancel(_:))
    for view in [nameLabel, statusLabel, progressBar, resumeButton, cancelButton]
    {
      addSubview(view)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func set(_ download: FiberDownloadState) {
    nameLabel.stringValue = download.fileName
    statusLabel.stringValue = download.statusText
    progressBar.progress = download.progress
    resumeButton.isHidden = !download.paused
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let size = Self.buttonSize
    cancelButton.frame = NSRect(
      x: bounds.maxX - size, y: (bounds.height - size) / 2, width: size,
      height: size)
    resumeButton.frame = cancelButton.frame.offsetBy(
      dx: -(size + Self.buttonSpacing), dy: 0)
    // Room for both buttons, so the bars line up whether or not it's paused.
    let textWidth = resumeButton.frame.minX - Self.textInset
    nameLabel.frame = NSRect(x: 0, y: 2, width: textWidth, height: 18)
    statusLabel.frame = NSRect(x: 0, y: 21, width: textWidth, height: 16)
    progressBar.frame = NSRect(
      x: 0, y: bounds.height - ProgressBar.height - 2, width: textWidth,
      height: ProgressBar.height)
  }

  private static func makeButton(symbol: String, label: String) -> NSButton {
    let image = NSImage(
      systemSymbolName: symbol, accessibilityDescription: label)!
    let button = NSButton(image: image, target: nil, action: nil)
    button.bezelStyle = .glass
    button.borderShape = .circle
    button.controlSize = .regular
    button.imageScaling = .scaleProportionallyDown
    button.setAccessibilityLabel(label)
    return button
  }

  @objc private func resume(_ sender: Any?) {
    onResume()
  }

  @objc private func cancel(_ sender: Any?) {
    onCancel()
  }
}

/// A thin capsule filling from the left; while the total isn't known, a
/// segment slides along it instead.
@MainActor
private final class ProgressBar: NSView {
  static let height: CGFloat = 4
  private static let indeterminateFraction: CGFloat = 0.3

  /// From 0 to 1, or negative when unknown.
  var progress: Double = 0 {
    didSet { needsLayout = true }
  }

  private let track = CALayer()
  private let fill = CALayer()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    track.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    fill.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
    track.masksToBounds = true
    track.addSublayer(fill)
    layer?.addSublayer(track)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func layout() {
    super.layout()
    let radius = bounds.height / 2
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    track.frame = bounds
    track.cornerRadius = radius
    fill.cornerRadius = radius
    CATransaction.commit()

    if progress < 0 {
      let width = bounds.width * Self.indeterminateFraction
      guard fill.animation(forKey: "slide") == nil || fill.bounds.width != width
      else {
        return
      }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      fill.anchorPoint = CGPoint(x: 0, y: 0)
      fill.frame = CGRect(x: -width, y: 0, width: width, height: bounds.height)
      CATransaction.commit()
      let slide = CABasicAnimation(keyPath: "position.x")
      slide.fromValue = -width
      slide.toValue = bounds.width
      slide.duration = 1.2
      slide.repeatCount = .infinity
      slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      fill.add(slide, forKey: "slide")
    } else {
      // Implicitly animated, so it creeps rather than jumps.
      fill.removeAnimation(forKey: "slide")
      fill.anchorPoint = CGPoint(x: 0, y: 0)
      fill.frame = CGRect(
        x: 0, y: 0, width: bounds.width * min(max(progress, 0), 1),
        height: bounds.height)
    }
  }
}

private class FlippedView: NSView {
  override var isFlipped: Bool { true }
}
