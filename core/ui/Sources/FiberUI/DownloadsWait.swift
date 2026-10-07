import AppKit
import FiberBridge
import SwiftUI

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

/// A quit, or a window's close, waiting for downloads to finish, as the
/// window's prompt bubble: each download's progress, Continue Browsing to stop
/// waiting, and Quit (or Close) Now to go ahead without them.
@MainActor
final class DownloadsWait: NSObject, FiberDownloadsWait {
  private enum ButtonID: Int {
    case continueBrowsing, proceedNow
  }

  private let actions: any FiberDownloadsWaitActions
  private weak var controller: BrowserWindowController?
  private let list = DownloadListModel()
  private let bubble: PromptBubble
  private var isClosed = false

  init(
    reason: FiberDownloadsWaitReason, window: NSWindow,
    actions: any FiberDownloadsWaitActions
  ) {
    self.actions = actions
    controller = BrowserWindowController.controller(for: window)
    let isQuit = reason == .quit
    bubble = PromptBubble(
      model: PromptBubbleModel(
        topic: .downloads,
        title: isQuit
          ? "Quitting when downloads finish" : "Closing when downloads finish",
        buttons: [
          FiberPromptButton(
            buttonID: ButtonID.continueBrowsing.rawValue,
            title: "Continue Browsing", role: .cancel),
          FiberPromptButton(
            buttonID: ButtonID.proceedNow.rawValue,
            title: isQuit ? "Quit Now" : "Close Now", role: .other),
        ],
        accessory: AnyView(DownloadList(model: list))))
    super.init()

    list.onCancel = { [weak self] id in
      self?.actions.cancelDownload(withID: id)
    }
    list.onResume = { [weak self] id in
      self?.actions.resumeDownload(withID: id)
    }
    bubble.model.onButton = { [weak self] buttonID in
      switch ButtonID(rawValue: buttonID) {
      case .proceedNow: self?.finish { $0.proceedNow() }
      default: self?.finish { $0.stopWaiting() }
      }
    }
    guard let controller else {
      // Nowhere to wait, so don't.
      DispatchQueue.main.async {
        self.finish { $0.stopWaiting() }
      }
      return
    }
    controller.present(bubble, forTabWithID: nil)
  }

  func setDownloads(_ downloads: [FiberDownloadState]) {
    list.downloads = downloads
    bubble.model.message =
      downloads.count == 1 ? "1 download left" : "\(downloads.count) downloads left"
  }

  func close() {
    guard !isClosed else {
      return
    }
    isClosed = true
    controller?.dismiss(bubble)
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

@MainActor
@Observable
private final class DownloadListModel {
  var downloads: [FiberDownloadState] = []
  @ObservationIgnored var onCancel: (String) -> Void = { _ in }
  @ObservationIgnored var onResume: (String) -> Void = { _ in }
}

/// The downloads being waited for, a row each, scrolling past a few.
private struct DownloadList: View {
  private static let rowHeight: CGFloat = 46
  private static let rowSpacing: CGFloat = 8
  private static let maxVisibleRows = 4

  let model: DownloadListModel

  var body: some View {
    let rows = min(model.downloads.count, Self.maxVisibleRows)
    ScrollView {
      VStack(spacing: Self.rowSpacing) {
        ForEach(model.downloads, id: \.downloadID) { download in
          DownloadRow(
            download: download,
            onCancel: { model.onCancel(download.downloadID) },
            onResume: { model.onResume(download.downloadID) }
          )
          .frame(height: Self.rowHeight)
        }
      }
    }
    .scrollIndicators(.automatic)
    .scrollBounceBehavior(.basedOnSize)
    .frame(
      height: max(
        CGFloat(rows) * (Self.rowHeight + Self.rowSpacing) - Self.rowSpacing, 0)
    )
  }
}

private struct DownloadRow: View {
  let download: FiberDownloadState
  let onCancel: () -> Void
  let onResume: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        Text(download.fileName)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)
        Group {
          if download.progress < 0 {
            ProgressView()
          } else {
            ProgressView(value: min(max(download.progress, 0), 1))
              .animation(.smooth.slowMotion, value: download.progress)
          }
        }
        .progressViewStyle(.linear)
        .controlSize(.mini)
        Text(download.statusText)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      // Room for both buttons, so the bars line up whether or not it's
      // paused.
      HStack(spacing: 4) {
        rowButton("play.fill", label: "Resume", action: onResume)
          .opacity(download.paused ? 1 : 0)
          .disabled(!download.paused)
        rowButton("xmark", label: "Cancel", action: onCancel)
      }
    }
  }

  private func rowButton(
    _ symbol: String, label: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .bold))
        .frame(width: 22, height: 22)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .controlSize(.small)
    .accessibilityLabel(label)
  }
}
