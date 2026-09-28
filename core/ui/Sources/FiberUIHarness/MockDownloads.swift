import AppKit
import FiberBridge

/// Stands in for Chrome's downloads, which a quit waits for.
@MainActor
final class MockDownloads: NSObject, FiberDownloadsWaitActions {
  private struct Download {
    let id: String
    let name: String
    var received: Double
    let total: Double?
    var paused: Bool
  }

  private static let names = [
    "Fiber-Nightly.dmg", "vacation-photos-2026.zip", "podcast-episode-41.mp3",
    "annual-report-final-final.pdf", "dataset.tar.gz", "wallpaper.heic",
  ]

  private var downloads: [Download]
  private var wait: (any FiberDownloadsWait)?
  private var timer: Timer?
  private var done: ((Bool) -> Void)?

  init(count: Int) {
    downloads = (0..<count).map { index in
      Download(
        id: "mock-\(index)",
        name: Self.names[index % Self.names.count],
        received: Double.random(in: 0...40),
        total: index == 2 ? nil : Double.random(in: 60...240),
        paused: index == 1)
    }
  }

  var isEmpty: Bool { downloads.isEmpty }

  /// Shows the downloads in `window` until they're done or the user stops
  /// waiting; `done` gets whether to go ahead.
  func wait(in window: NSWindow, then done: @escaping (Bool) -> Void) {
    self.done = done
    wait = FiberDownloadsWaitFactory.wait(
      with: .quit, window: window, actions: self)
    push()
    timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
  }

  private func tick() {
    for index in downloads.indices where !downloads[index].paused {
      downloads[index].received += Double.random(in: 1...6)
    }
    downloads.removeAll { download in
      download.total.map { download.received >= $0 } ?? false
    }
    push()
  }

  private func push() {
    guard !downloads.isEmpty else {
      finish(true)
      return
    }
    wait?.setDownloads(
      downloads.map { download in
        let status =
          if download.paused {
            "Paused"
          } else if let total = download.total {
            String(format: "%.1f/%.0f MB, a few secs left", download.received, total)
          } else {
            String(format: "%.1f MB", download.received)
          }
        return FiberDownloadState(
          downloadID: download.id, fileName: download.name, statusText: status,
          progress: download.total.map { download.received / $0 } ?? -1,
          paused: download.paused)
      })
  }

  private func finish(_ proceed: Bool) {
    timer?.invalidate()
    timer = nil
    wait?.close()
    wait = nil
    let done = self.done
    self.done = nil
    done?(proceed)
  }

  // MARK: FiberDownloadsWaitActions

  func cancelDownload(withID downloadID: String) {
    downloads.removeAll { $0.id == downloadID }
    push()
  }

  func resumeDownload(withID downloadID: String) {
    if let index = downloads.firstIndex(where: { $0.id == downloadID }) {
      downloads[index].paused = false
    }
    push()
  }

  func proceedNow() {
    downloads = []
    finish(true)
  }

  func stopWaiting() {
    finish(false)
  }
}
