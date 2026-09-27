import AVFoundation
import CryptoKit
import VideoToolbox

// VideoToolbox's decode of an 8-bit H.264 or HEVC file, as index.py's second
// reference: prints each frame's luma SHA-256 (packed, as the test page
// hashes it), in presentation order. Software decoding is allowed, as Fiber
// allows it.
//   vtref file.mp4
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sema = DispatchSemaphore(value: 0)
Task {
  let track = try! await asset.loadTracks(withMediaType: .video)[0]
  let fmt = try! await track.load(.formatDescriptions)[0]
  let spec: [CFString: Any] = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true]
  let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
  var session: VTDecompressionSession?
  precondition(VTDecompressionSessionCreate(allocator: nil, formatDescription: fmt, decoderSpecification: spec as CFDictionary,
                                            imageBufferAttributes: attrs as CFDictionary, outputCallback: nil, decompressionSessionOut: &session) == noErr)
  var lines: [(Int64, String)] = []
  let lock = NSLock()
  let reader = try! AVAssetReader(asset: asset)
  let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
  reader.add(out); reader.startReading()
  while let sb = out.copyNextSampleBuffer() {
    if CMSampleBufferGetNumSamples(sb) == 0 { continue }
    _ = VTDecompressionSessionDecodeFrame(session!, sampleBuffer: sb, flags: [], infoFlagsOut: nil) { status, _, image, pts, _ in
      guard status == noErr, let img = image else { FileHandle.standardError.write("error \(status)\n".data(using: .utf8)!); exit(1) }
      CVPixelBufferLockBaseAddress(img, .readOnly)
      let w = CVPixelBufferGetWidthOfPlane(img, 0), h = CVPixelBufferGetHeightOfPlane(img, 0)
      let stride = CVPixelBufferGetBytesPerRowOfPlane(img, 0)
      let base = CVPixelBufferGetBaseAddressOfPlane(img, 0)!.assumingMemoryBound(to: UInt8.self)
      var packed = Data(capacity: w * h)
      for y in 0..<h { packed.append(base + y * stride, count: w) }
      CVPixelBufferUnlockBaseAddress(img, .readOnly)
      let hash = SHA256.hash(data: packed).map { String(format: "%02x", $0) }.joined()
      lock.lock(); lines.append((Int64(pts.seconds * 1e6 + 0.5), hash)); lock.unlock()
    }
  }
  VTDecompressionSessionWaitForAsynchronousFrames(session!)
  for (_, h) in lines.sorted(by: { $0.0 < $1.0 }) { print(h) }
  sema.signal()
}
sema.wait()
