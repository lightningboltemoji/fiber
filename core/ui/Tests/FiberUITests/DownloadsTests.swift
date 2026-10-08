import FiberBridge
import Foundation
import Testing

@testable import FiberUI

struct DownloadsTests {
  private static func download(
    _ id: String, _ status: FiberDownloadStatus, received: Int64 = 0,
    total: Int64 = 0, timeRemaining: TimeInterval = -1, paused: Bool = false,
    origin: String = "", statusText: String = "", fileMissing: Bool = false
  ) -> FiberDownloadState {
    FiberDownloadState(
      downloadID: id, fileName: "\(id).zip", filePath: "/tmp/\(id).zip",
      status: status, statusText: statusText, warningText: "", origin: origin,
      receivedBytes: received, totalBytes: total,
      progress: total > 0 ? Double(received) / Double(total) : -1,
      timeRemaining: timeRemaining, paused: paused, canResume: false,
      canRetry: false, canKeep: false, fileMissing: fileMissing)
  }

  @Test func saysNothingWithoutDownloads() {
    #expect(DownloadsSummary(downloads: []) == nil)
  }

  @Test func countsThoseInProgressWithTheirProgressTogether() {
    let summary = DownloadsSummary(downloads: [
      Self.download("a", .inProgress, received: 30, total: 100),
      Self.download("b", .inProgress, received: 10, total: 100),
      // Its size isn't known, so it doesn't count toward the progress.
      Self.download("c", .inProgress, received: 500),
      Self.download("d", .complete, received: 5, total: 5),
    ])
    #expect(summary?.title == "3 in progress")
    #expect(summary?.indicator == .progress(0.2))
  }

  @Test func hasNoProgressWhileNoSizeIsKnown() {
    let summary = DownloadsSummary(downloads: [
      Self.download("a", .inProgress, received: 30)
    ])
    #expect(summary?.indicator == .progress(nil))
  }

  @Test func saysWhenAllInProgressArePaused() {
    let summary = DownloadsSummary(downloads: [
      Self.download("a", .inProgress, received: 50, total: 100, paused: true)
    ])
    #expect(summary?.title == "1 paused")
    #expect(summary?.indicator == .paused(0.5))
  }

  @Test func asksForReviewFirst() {
    let summary = DownloadsSummary(downloads: [
      Self.download("a", .needsReview),
      Self.download("b", .inProgress, received: 1, total: 2),
    ])
    #expect(summary?.title == "Review download")
    #expect(summary?.indicator == .review)
  }

  @Test func countsThemAllOnceDone() {
    let downloads = (0..<5).map { Self.download("\($0)", .complete) }
    let summary = DownloadsSummary(downloads: downloads)
    #expect(summary?.title == "5 downloads")
    #expect(
      summary?.indicator == .files(count: DownloadsSummary.maxFanned))
    #expect(
      DownloadsSummary(downloads: downloads, justFinished: true)?.indicator
        == .finished)
    #expect(
      DownloadsSummary(downloads: [Self.download("a", .failed)])?.title
        == "1 download")
  }

  @Test func describesEachRow() {
    #expect(
      DownloadText.subtitle(
        for: Self.download(
          "a", .inProgress, received: 2_000_000, total: 10_000_000,
          timeRemaining: 90)) == "2 MB of 10 MB · 2 min left")
    #expect(
      DownloadText.subtitle(
        for: Self.download("a", .inProgress, received: 2_000_000, paused: true))
        == "Paused · 2 MB")
    #expect(
      DownloadText.subtitle(
        for: Self.download(
          "a", .complete, received: 3_000_000, total: 3_000_000,
          origin: "example.com")) == "3 MB · example.com")
    #expect(
      DownloadText.subtitle(
        for: Self.download("a", .complete, fileMissing: true)) == "Deleted")
    #expect(
      DownloadText.subtitle(
        for: Self.download(
          "a", .failed, statusText: "Failed - Network error"))
        == "Failed - Network error")
  }

  @Test func estimatesTimeLeftInOneUnit() {
    #expect(DownloadText.timeLeft(-1) == nil)
    #expect(DownloadText.timeLeft(0.2) == "1 sec left")
    #expect(DownloadText.timeLeft(45) == "45 sec left")
    #expect(DownloadText.timeLeft(150) == "3 min left")
    #expect(DownloadText.timeLeft(3700) == "1 hr left")
  }

  @Test func opensPanelUpAndLeftFromTheCapsule() {
    let capsule = CGRect(x: 700, y: 600, width: 140, height: 40)
    let panel = DownloadsLayout.panelFrame(capsule: capsule, rows: 2)
    #expect(panel.maxX == capsule.maxX)
    #expect(panel.maxY == capsule.maxY)
    #expect(panel.width == DownloadsLayout.panelWidth)
    #expect(
      panel.height
        == DownloadsLayout.footerHeight + DownloadsLayout.listHeight(rows: 2))
  }

  @Test func panelScrollsPastAFewRowsAndFitsTheWindow() {
    let capsule = CGRect(x: 700, y: 600, width: 140, height: 40)
    let many = DownloadsLayout.panelFrame(capsule: capsule, rows: 40)
    #expect(
      many.height
        == DownloadsLayout.footerHeight
        + DownloadsLayout.listHeight(rows: DownloadsLayout.maxVisibleRows))
    // Near the window's top-left corner, it stops short of its edges.
    let cramped = CGRect(x: 100, y: 100, width: 140, height: 40)
    let fitted = DownloadsLayout.panelFrame(capsule: cramped, rows: 40)
    #expect(fitted.minX == DownloadsLayout.margin)
    #expect(fitted.minY == DownloadsLayout.margin)
  }

  @MainActor @Test func capsuleFitsWhatItSays() {
    let short = DownloadsSummary(downloads: [Self.download("a", .complete)])!
    let long = DownloadsSummary(
      downloads: (0..<12).map { Self.download("\($0)", .inProgress) })!
    #expect(
      DownloadsLayout.capsuleWidth(for: long)
        > DownloadsLayout.capsuleWidth(for: short))
    #expect(DownloadsLayout.capsuleWidth(for: short) > GlassCapsule.height)
  }
}
