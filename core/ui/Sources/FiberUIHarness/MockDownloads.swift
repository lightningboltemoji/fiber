import AppKit
import FiberBridge

/// Stands in for the profile's downloads: listed in its windows' tab
/// overlays, as FiberDownloads lists them, and waited for when quitting, as
/// DownloadsWait waits.
@MainActor
final class MockDownloads: NSObject, FiberDownloadsActions,
  FiberDownloadsWaitActions
{
  private struct Download {
    let id: String
    let name: String
    let origin: String
    /// In MB.
    var received: Double
    var total: Double?
    var status: FiberDownloadStatus
    var paused = false
    var canResume = false
    var statusText = ""
  }

  private static let names = [
    "Fiber-Nightly.dmg", "vacation-photos-2026.zip", "podcast-episode-41.mp3",
    "annual-report-final-final.pdf", "dataset.tar.gz", "wallpaper.heic",
    "setup.pkg", "keynote-recording.mov",
  ]
  private static let origins = [
    "fiber.example", "photos.example", "podcasts.example", "news.example",
  ]

  /// Newest first.
  private var downloads: [Download] = []
  private var nextID = 0
  private let lists = NSHashTable<AnyObject>.weakObjects()
  private var wait: (any FiberDownloadsWait)?
  private var done: ((Bool) -> Void)?
  private var timer: Timer?

  /// `count` made-up downloads, in all the states one can be in.
  init(count: Int) {
    super.init()
    for index in (0..<count).reversed() {
      downloads.append(Self.sample(index, id: "mock-\(index)"))
    }
    nextID = count
    updateTimer()
  }

  var hasInProgress: Bool {
    downloads.contains { $0.status == .inProgress }
  }

  /// Lists the downloads in a window's tab overlay from now on.
  func attach(_ list: any FiberDownloads) {
    list.actions = self
    lists.add(list)
    list.setDownloads(states(of: listed))
  }

  /// A new download, as one the user just picked where to save.
  func add() {
    let index = nextID
    nextID += 1
    let name = Self.names[index % Self.names.count]
    downloads.insert(
      Download(
        id: "mock-\(index)", name: name,
        origin: Self.origins[index % Self.origins.count], received: 0,
        total: Double.random(in: 30...160), status: .inProgress),
      at: 0)
    push()
    updateTimer()
  }

  /// Shows the downloads in progress in `window` until they're done or the
  /// user stops waiting; `done` gets whether to go ahead.
  func wait(in window: NSWindow, then done: @escaping (Bool) -> Void) {
    self.done = done
    wait = FiberDownloadsWaitFactory.wait(
      with: .quit, window: window, actions: self)
    push()
  }

  private static func sample(_ index: Int, id: String) -> Download {
    let name = names[index % names.count]
    let origin = origins[index % origins.count]
    var download = Download(
      id: id, name: name, origin: origin, received: 0, total: nil,
      status: .complete)
    switch index % 8 {
    case 0:
      download.status = .inProgress
      download.received = Double.random(in: 10...40)
      download.total = 180
    case 1:
      download.status = .inProgress
      download.received = 40
      download.total = 90
      download.paused = true
    case 2:
      download.status = .inProgress
      download.received = Double.random(in: 2...10)
    case 4:
      download.status = .failed
      download.received = 120
      download.total = 300
      download.canResume = true
      download.statusText = "Failed - Network error"
    case 5:
      download.status = .needsReview
      download.received = 4.2
      download.total = 4.2
    case 6:
      download.status = .cancelled
      download.received = 12
      download.total = 64
      download.statusText = "Cancelled"
    default:
      download.received = Double.random(in: 0.3...30)
      download.total = download.received
    }
    return download
  }

  /// In progress or waiting on review first, then the rest, as the browser
  /// lists them.
  private var listed: [Download] {
    let isActive = { (download: Download) in
      download.status == .inProgress || download.status == .needsReview
    }
    return downloads.filter(isActive) + downloads.filter { !isActive($0) }
  }

  private func states(of downloads: [Download]) -> [FiberDownloadState] {
    downloads.map { download in
      let megabytes = { (value: Double) in Int64(value * 1_000_000) }
      let remaining =
        download.total.map { ($0 - download.received) / Self.speed } ?? -1
      let statusText =
        download.statusText.isEmpty
        ? download.paused
          ? "Paused"
          : String(format: "%.1f MB, a few secs left", download.received)
        : download.statusText
      return FiberDownloadState(
        downloadID: download.id, fileName: download.name,
        filePath: NSHomeDirectory() + "/Downloads/" + download.name,
        status: download.status, statusText: statusText,
        warningText: download.status == .needsReview
          ? "This type of file can harm your computer. Do you want to keep "
            + "\(download.name) anyway?" : "",
        origin: download.origin,
        receivedBytes: megabytes(download.received),
        totalBytes: download.total.map(megabytes) ?? 0,
        progress: download.total.map { download.received / $0 } ?? -1,
        timeRemaining: download.paused ? -1 : remaining,
        paused: download.paused, canResume: download.canResume,
        canRetry: download.status == .failed || download.status == .cancelled,
        canKeep: true, fileMissing: false)
    }
  }

  /// MB a second, on average.
  private static let speed = 14.0
  private static let tick: TimeInterval = 0.25

  private func updateTimer() {
    let isDownloading = downloads.contains {
      $0.status == .inProgress && !$0.paused
    }
    if isDownloading, timer == nil {
      timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true)
      { [weak self] _ in
        MainActor.assumeIsolated { self?.step() }
      }
    } else if !isDownloading {
      timer?.invalidate()
      timer = nil
    }
  }

  private func step() {
    for index in downloads.indices
    where downloads[index].status == .inProgress && !downloads[index].paused {
      downloads[index].received +=
        Double.random(in: 0.2...1.8) * Self.speed * Self.tick
      let total = downloads[index].total ?? 60
      if downloads[index].received >= total {
        downloads[index].received = total
        downloads[index].total = total
        downloads[index].status = .complete
      }
    }
    push()
    updateTimer()
  }

  private func push() {
    let states = states(of: listed)
    for case let list as any FiberDownloads in lists.allObjects {
      list.setDownloads(states)
    }
    guard wait != nil else {
      return
    }
    let inProgress = listed.filter { $0.status == .inProgress }
    guard !inProgress.isEmpty else {
      finish(true)
      return
    }
    wait?.setDownloads(self.states(of: inProgress))
  }

  private func finish(_ proceed: Bool) {
    wait?.close()
    wait = nil
    let done = self.done
    self.done = nil
    done?(proceed)
  }

  private func update(_ id: String, _ change: (inout Download) -> Void) {
    guard let index = downloads.firstIndex(where: { $0.id == id }) else {
      return
    }
    change(&downloads[index])
    push()
    updateTimer()
  }

  private func name(of id: String) -> String {
    downloads.first { $0.id == id }?.name ?? id
  }

  // MARK: FiberDownloadsActions

  func openDownload(withID downloadID: String) {
    print("Open \(name(of: downloadID))")
  }

  func showDownloadInFinder(withID downloadID: String) {
    print("Show \(name(of: downloadID)) in Finder")
  }

  func pauseDownload(withID downloadID: String) {
    update(downloadID) { $0.paused = true }
  }

  func resumeDownload(withID downloadID: String) {
    update(downloadID) { download in
      download.paused = false
      if download.status == .failed {
        download.status = .inProgress
        download.statusText = ""
      }
    }
  }

  func cancelDownload(withID downloadID: String) {
    update(downloadID) { download in
      download.status = .cancelled
      download.paused = false
      download.statusText = "Cancelled"
    }
  }

  /// As the browser does, a new download of the same file.
  func retryDownload(withID downloadID: String) {
    guard let old = downloads.first(where: { $0.id == downloadID }) else {
      return
    }
    downloads.insert(
      Download(
        id: "mock-\(nextID)", name: old.name, origin: old.origin, received: 0,
        total: old.total ?? 50, status: .inProgress),
      at: 0)
    nextID += 1
    push()
    updateTimer()
  }

  func keepDownload(withID downloadID: String) {
    update(downloadID) { $0.status = .complete }
  }

  func discardDownload(withID downloadID: String) {
    downloads.removeAll { $0.id == downloadID }
    push()
  }

  func removeDownload(withID downloadID: String) {
    downloads.removeAll {
      $0.id == downloadID && $0.status != .inProgress
        && $0.status != .needsReview
    }
    push()
  }

  func clearDownloads() {
    downloads.removeAll {
      $0.status != .inProgress && $0.status != .needsReview
    }
    push()
  }

  func showAllDownloads() {
    print("Show the Downloads page")
  }

  func downloadsDidShow() {}

  // MARK: FiberDownloadsWaitActions

  func proceedNow() {
    for index in downloads.indices
    where downloads[index].status == .inProgress {
      downloads[index].status = .cancelled
      downloads[index].statusText = "Cancelled"
    }
    finish(true)
    push()
    updateTimer()
  }

  func stopWaiting() {
    finish(false)
  }
}
