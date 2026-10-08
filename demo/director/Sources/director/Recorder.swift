import AVFoundation
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Seconds on the host clock, which ScreenCaptureKit stamps frames with, so
/// the timeline and the take agree to the frame.
func hostNow() -> Double {
  CMClockGetTime(CMClockGetHostTimeClock()).seconds
}

/// Records one window, without its shadow, into an HEVC movie at the
/// window's pixel size. ScreenCaptureKit sends only frames that changed, so the
/// movie's frame rate varies; each frame keeps its host time.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  private let queue = DispatchQueue(label: "recorder")
  private let filter: SCContentFilter
  private let configuration = SCStreamConfiguration()
  private var stream: SCStream?
  private var writer: AVAssetWriter
  private var input: AVAssetWriterInput
  /// Guarded by `queue`.
  private var firstTime: Double?
  private var lastTime: CMTime = .zero
  private var waiting: CheckedContinuation<Double, Never>?
  private(set) var frames = 0
  private(set) var dropped = 0
  private(set) var failure: Error?

  let pixelSize: CGSize

  init(window: SCWindow, to url: URL, fps: Int, showsCursor: Bool) throws {
    filter = SCContentFilter(desktopIndependentWindow: window)
    let scale = CGFloat(filter.pointPixelScale)
    pixelSize = CGSize(width: (window.frame.width * scale).rounded(), height: (window.frame.height * scale).rounded())
    configuration.width = Int(pixelSize.width)
    configuration.height = Int(pixelSize.height)
    configuration.ignoreShadowsSingleWindow = true
    configuration.showsCursor = showsCursor
    configuration.captureResolution = .best
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    configuration.queueDepth = 8
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.colorSpaceName = CGColorSpace.sRGB

    try? FileManager.default.removeItem(at: url)
    writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: configuration.width,
        AVVideoHeightKey: configuration.height,
        AVVideoColorPropertiesKey: [
          AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
          AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
          AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
        AVVideoCompressionPropertiesKey: [
          AVVideoQualityKey: 0.92,
          AVVideoExpectedSourceFrameRateKey: fps,
          AVVideoMaxKeyFrameIntervalKey: fps,
          AVVideoAllowFrameReorderingKey: false,
        ],
      ])
    input.expectsMediaDataInRealTime = true
    writer.add(input)
    super.init()
  }

  /// The window as it is now, with its rounded corners clear: the studio
  /// masks the take with it.
  func snapshot(to url: URL) async throws {
    let still = SCStreamConfiguration()
    still.width = configuration.width
    still.height = configuration.height
    still.ignoreShadowsSingleWindow = true
    still.showsCursor = false
    still.captureResolution = .best
    still.shouldBeOpaque = false
    still.colorSpaceName = CGColorSpace.sRGB
    let image: CGImage = try await withCheckedThrowingContinuation { continuation in
      SCScreenshotManager.captureImage(contentFilter: filter, configuration: still) { image, error in
        if let image {
          continuation.resume(returning: image)
        } else {
          continuation.resume(throwing: error ?? CocoaError(.featureUnsupported))
        }
      }
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
      throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
  }

  /// Starts recording; returns the host time of the first frame, where the
  /// take begins.
  func start() async throws -> Double {
    guard writer.startWriting() else {
      throw writer.error ?? CocoaError(.fileWriteUnknown)
    }
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    self.stream = stream
    try await stream.startCapture()
    return await withCheckedContinuation { continuation in
      queue.async {
        if let first = self.firstTime {
          continuation.resume(returning: first)
        } else {
          self.waiting = continuation
        }
      }
    }
  }

  /// Stops at `end` (host time), so a take that ends on a still frame
  /// still lasts until then.
  func stop(at end: Double) async throws {
    try await stream?.stopCapture()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      queue.async { continuation.resume() }
    }
    input.markAsFinished()
    let endTime = CMTime(seconds: end, preferredTimescale: 600_000)
    writer.endSession(atSourceTime: CMTimeMaximum(endTime, lastTime))
    await writer.finishWriting()
    if writer.status == .failed {
      throw writer.error ?? CocoaError(.fileWriteUnknown)
    }
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, buffer.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
        as? [[SCStreamFrameInfo: Any]],
      let raw = attachments.first?[.status] as? Int,
      SCFrameStatus(rawValue: raw) == .complete
    else {
      return
    }
    let time = buffer.presentationTimeStamp
    if firstTime == nil {
      firstTime = time.seconds
      writer.startSession(atSourceTime: time)
      waiting?.resume(returning: time.seconds)
      waiting = nil
    }
    guard input.isReadyForMoreMediaData else {
      dropped += 1
      return
    }
    if input.append(buffer) {
      frames += 1
      lastTime = time
    } else {
      dropped += 1
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    queue.async { self.failure = error }
  }
}
