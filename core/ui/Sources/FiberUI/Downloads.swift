import AppKit
import FiberBridge
import UniformTypeIdentifiers

@objc @implementation extension FiberDownloadState {
  let downloadID: String
  let fileName: String
  let filePath: String
  let status: FiberDownloadStatus
  let statusText: String
  let warningText: String
  let origin: String
  let receivedBytes: Int64
  let totalBytes: Int64
  let progress: Double
  let timeRemaining: TimeInterval
  let paused: Bool
  let canResume: Bool
  let canRetry: Bool
  let canKeep: Bool
  let fileMissing: Bool

  init(
    downloadID: String, fileName: String, filePath: String,
    status: FiberDownloadStatus, statusText: String, warningText: String,
    origin: String, receivedBytes: Int64, totalBytes: Int64, progress: Double,
    timeRemaining: TimeInterval, paused: Bool, canResume: Bool,
    canRetry: Bool, canKeep: Bool, fileMissing: Bool
  ) {
    self.downloadID = downloadID
    self.fileName = fileName
    self.filePath = filePath
    self.status = status
    self.statusText = statusText
    self.warningText = warningText
    self.origin = origin
    self.receivedBytes = receivedBytes
    self.totalBytes = totalBytes
    self.progress = progress
    self.timeRemaining = timeRemaining
    self.paused = paused
    self.canResume = canResume
    self.canRetry = canRetry
    self.canKeep = canKeep
    self.fileMissing = fileMissing
    super.init()
  }
}

/// The window's downloads, from the browser, which the tab overlay lists.
@MainActor
final class WindowDownloads: NSObject, FiberDownloads {
  var actions: (any FiberDownloadsActions)?
  var onChange: ([FiberDownloadState]) -> Void = { _ in }

  func setDownloads(_ downloads: [FiberDownloadState]) {
    onChange(downloads)
  }

  func didShow() {
    actions?.downloadsDidShow()
  }

  func perform(_ action: DownloadAction) {
    guard let actions else {
      return
    }
    switch action {
    case .open(let id): actions.openDownload(withID: id)
    case .showInFinder(let id): actions.showDownloadInFinder(withID: id)
    case .pause(let id): actions.pauseDownload(withID: id)
    case .resume(let id): actions.resumeDownload(withID: id)
    case .cancel(let id): actions.cancelDownload(withID: id)
    case .retry(let id): actions.retryDownload(withID: id)
    case .keep(let id): actions.keepDownload(withID: id)
    case .discard(let id): actions.discardDownload(withID: id)
    case .remove(let id): actions.removeDownload(withID: id)
    case .clear: actions.clearDownloads()
    case .showAll: actions.showAllDownloads()
    }
  }
}

/// What the user does in the downloads list, each with a download's ID.
enum DownloadAction: Equatable {
  case open(String)
  case showInFinder(String)
  case pause(String)
  case resume(String)
  case cancel(String)
  case retry(String)
  case keep(String)
  case discard(String)
  case remove(String)
  case clear
  case showAll

  /// Whether it takes the user elsewhere: another app, the Finder, a tab.
  var leavesOverlay: Bool {
    switch self {
    case .open, .showInFinder, .showAll: true
    default: false
    }
  }
}

extension FiberDownloadState {
  var fileURL: URL? {
    filePath.isEmpty ? nil : URL(fileURLWithPath: filePath)
  }

  /// Opening it opens the file.
  var canOpen: Bool {
    status == .complete && !fileMissing && fileURL != nil
  }

  /// Not in progress, nor waiting on review: it can come off the list.
  var isInactive: Bool {
    status != .inProgress && status != .needsReview
  }
}

/// What the downloads capsule says: how many downloads there are, and how far
/// along those in progress are.
struct DownloadsSummary: Equatable {
  enum Indicator: Equatable {
    /// How far along the downloads in progress are together: nil while none
    /// of their sizes is known.
    case progress(Double?)
    case paused(Double?)
    case review
    /// The last download in progress just finished.
    case finished
    /// The icons of the most recent `count` files.
    case files(count: Int)
  }

  /// At most this many files' icons fan out.
  static let maxFanned = 3

  /// The number the title counts, which rolls as it changes.
  let count: Int
  let title: String
  let indicator: Indicator

  /// Nil for no downloads. `justFinished` is whether the last download in
  /// progress finished a moment ago.
  init?(downloads: [FiberDownloadState], justFinished: Bool = false) {
    guard !downloads.isEmpty else {
      return nil
    }
    let review = downloads.filter { $0.status == .needsReview }
    let active = downloads.filter { $0.status == .inProgress }
    if !review.isEmpty {
      count = review.count
      title = count == 1 ? "Review download" : "Review \(count) downloads"
      indicator = .review
    } else if !active.isEmpty {
      count = active.count
      let progress = Self.progress(of: active)
      if active.allSatisfy(\.paused) {
        title = "\(count) paused"
        indicator = .paused(progress)
      } else {
        title = "\(count) in progress"
        indicator = .progress(progress)
      }
    } else {
      count = downloads.count
      title = count == 1 ? "1 download" : "\(count) downloads"
      indicator =
        justFinished
        ? .finished : .files(count: min(count, Self.maxFanned))
    }
  }

  /// The bytes in, of those whose size is known.
  private static func progress(of downloads: [FiberDownloadState]) -> Double? {
    let sized = downloads.filter { $0.totalBytes > 0 }
    guard !sized.isEmpty else {
      return nil
    }
    let total = sized.reduce(0) { $0 + Double($1.totalBytes) }
    let received = sized.reduce(0) {
      $0 + Double(min($1.receivedBytes, $1.totalBytes))
    }
    return received / total
  }
}

/// How a download's row describes it.
enum DownloadText {
  /// Its second line: how far along it is, or where it came from.
  static func subtitle(for download: FiberDownloadState) -> String {
    switch download.status {
    case .inProgress:
      let amount = amount(for: download)
      if download.paused {
        return "Paused · \(amount)"
      }
      return [amount, timeLeft(download.timeRemaining)]
        .compactMap { $0 }.joined(separator: " · ")
    case .needsReview:
      return "May be harmful"
    case .complete:
      if download.fileMissing {
        return "Deleted"
      }
      let size = max(download.totalBytes, download.receivedBytes)
      return [bytes(size), download.origin]
        .filter { !$0.isEmpty }.joined(separator: " · ")
    case .failed, .cancelled:
      return download.statusText
    @unknown default:
      return download.statusText
    }
  }

  /// "12.3 MB of 45.6 MB", or just what's in while the size isn't known.
  static func amount(for download: FiberDownloadState) -> String {
    let received = bytes(download.receivedBytes)
    guard download.totalBytes > 0 else {
      return received
    }
    return "\(received) of \(bytes(download.totalBytes))"
  }

  static func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
  }

  private static let timeFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .short
    formatter.maximumUnitCount = 1
    return formatter
  }()

  /// "2 min left", or nil while there's no estimate.
  static func timeLeft(_ seconds: TimeInterval) -> String? {
    guard seconds >= 0 else {
      return nil
    }
    return timeFormatter.string(from: max(seconds.rounded(.up), 1)).map {
      "\($0) left"
    }
  }
}

/// The icons for downloads' files: a finished file's own, or its kind's.
@MainActor
enum DownloadFileIcon {
  private static var cache: [String: NSImage] = [:]

  static func image(for download: FiberDownloadState) -> NSImage {
    if download.canOpen, let url = download.fileURL,
      FileManager.default.fileExists(atPath: url.path)
    {
      return cached("file:\(url.path)") {
        NSWorkspace.shared.icon(forFile: url.path)
      }
    }
    let fileExtension = (download.fileName as NSString).pathExtension
      .lowercased()
    return cached("type:\(fileExtension)") {
      NSWorkspace.shared.icon(
        for: UTType(filenameExtension: fileExtension) ?? .data)
    }
  }

  private static func cached(_ key: String, _ make: () -> NSImage) -> NSImage
  {
    if let image = cache[key] {
      return image
    }
    let image = make()
    cache[key] = image
    return image
  }
}
