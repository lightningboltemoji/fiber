#ifndef FIBER_MEDIA_VIDEO_PASSTHROUGH_DECODER_H_
#define FIBER_MEDIA_VIDEO_PASSTHROUGH_DECODER_H_

#include <CoreMedia/CoreMedia.h>
#include <stddef.h>
#include <stdint.h>

#include <memory>
#include <optional>
#include <vector>

#include "base/apple/scoped_cftyperef.h"
#include "base/containers/span.h"
#include "base/memory/raw_span.h"
#include "base/memory/scoped_refptr.h"
#include "base/time/time.h"
#include "fiber/media/hooks/video_toolbox_decoder.h"
#include "media/base/decoder_buffer.h"
#include "media/base/video_codecs.h"
#include "media/base/video_color_space.h"
#include "media/base/video_types.h"
#include "media/gpu/accelerated_video_decoder.h"
#include "media/gpu/codec_picture.h"
#include "media/gpu/mac/video_toolbox_decompression_metadata.h"
#include "media/gpu/mac/video_toolbox_nalu_util.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/hdr_metadata.h"

namespace media {
class MediaLog;
}  // namespace media

namespace fiber {

// Drives Chromium's VideoToolbox decoder for H.264 and HEVC in place of
// H264Decoder and H265Decoder, which run each standard's decoded picture
// buffer process (reference marking, reference lists, picture order counts).
// VideoToolbox does all of that itself; this only parses parameter sets,
// hands VideoToolbox each frame, and puts the frames in presentation order
// by their timestamps, as Firefox does on macOS.
//
// Each input buffer is one frame (Chromium's demuxers, WebCodecs and WebRTC
// all deliver whole frames), in Annex B, since VideoToolboxVideoDecoder asks
// for bitstream conversion. Subclasses parse a codec's buffers; this does
// the rest.
class PassthroughDecoder : public media::AcceleratedVideoDecoder {
 public:
  ~PassthroughDecoder() override;

  // AcceleratedVideoDecoder:
  void SetStream(int32_t id,
                 scoped_refptr<media::DecoderBuffer> decoder_buffer) final;
  bool Flush() final;
  void Reset() final;
  DecodeResult Decode() final;
  gfx::Size GetPicSize() const final;
  gfx::Rect GetVisibleRect() const final;
  media::VideoCodecProfile GetProfile() const final;
  uint8_t GetBitDepth() const final;
  media::VideoChromaSampling GetChromaSampling() const final;
  media::VideoColorSpace GetVideoColorSpace() const final;
  size_t GetRequiredNumOfPictures() const final;
  size_t GetNumReferenceFrames() const final;

 protected:
  // What a frame's sequence parameter set says about it.
  struct Config {
    gfx::Size pic_size;
    gfx::Rect visible_rect;
    media::VideoCodecProfile profile = media::VIDEO_CODEC_PROFILE_UNKNOWN;
    uint8_t bit_depth = 8;
    media::VideoChromaSampling chroma_sampling =
        media::VideoChromaSampling::k420;
    media::VideoColorSpace color_space;
    // How many frames the decoded picture buffer holds.
    size_t dpb_size = 0;
    // How many frames can precede a frame in decoding order and follow it in
    // presentation order: how many to hold back before the earliest is sure
    // to be next.
    size_t max_reorder = 0;
  };

  // One input buffer, as a subclass finds it.
  struct Frame {
    Frame();
    ~Frame();

    // Its slices (VCL NAL units), in order.
    std::vector<base::raw_span<const uint8_t>> nalus;
    Config config;
    // Metadata for a decompression session made for this frame's format.
    media::VideoToolboxDecompressionSessionMetadata session_metadata;
    // A frame decoding can start at (H.264's IDR, HEVC's IRAP). Only these
    // take a new format when a parameter set changes.
    bool keyframe = false;
    // The first frame of a coded video sequence: every frame before it comes
    // out first.
    bool starts_sequence = false;
    // False for a frame that's decoded but never shown.
    bool shown = true;
    // Flag the frame for VideoToolbox to reset before decoding it, if it's
    // the first since a reset.
    bool reset_decoder = false;
  };

  enum class ParseResult {
    kOk,
    // Nothing to decode: no slices, or a frame decoding can't start at.
    kSkip,
    kError,
  };

  PassthroughDecoder(std::unique_ptr<media::MediaLog> media_log,
                     VideoToolboxDecodeCB decode_cb,
                     VideoToolboxOutputCB output_cb,
                     const media::VideoColorSpace& container_color_space);

  // Parses `buffer` into `frame`: records the parameter sets it carries in
  // the trackers below, and the ones its slices use.
  virtual ParseResult Parse(const media::DecoderBuffer& buffer,
                            Frame& frame) = 0;

  // A format for the parameter sets the frame uses, in the trackers' order.
  virtual base::apple::ScopedCFTypeRef<CMFormatDescriptionRef> CreateFormat(
      const std::vector<const uint8_t*>& parameter_sets,
      const std::vector<size_t>& parameter_set_sizes,
      const Frame& frame) = 0;

  // After a reset: wait for a frame decoding can start at.
  virtual void OnReset() = 0;

  // The stream's color space, where its parameter sets don't give one.
  const media::VideoColorSpace& container_color_space() const {
    return container_color_space_;
  }

  // The dynamic HDR metadata the stream's SEI messages carry.
  gfx::HDRMetadata& hdr_metadata() { return hdr_metadata_; }

  media::MediaLog* media_log() { return media_log_.get(); }

  // Parameter sets seen, and the ones the current frame uses. HEVC uses all
  // three; H.264 has no VPS.
  media::VideoToolboxParameterSetTracker& vps_tracker() { return vps_tracker_; }
  media::VideoToolboxParameterSetTracker& sps_tracker() { return sps_tracker_; }
  media::VideoToolboxParameterSetTracker& pps_tracker() { return pps_tracker_; }

 private:
  // A decoded frame waiting for its turn to be shown.
  struct Pending {
    base::TimeDelta timestamp;
    uint64_t decode_order;
    scoped_refptr<media::CodecPicture> picture;
  };

  // Hands `frame_` to VideoToolbox. False on failure.
  bool Submit();

  // Schedules pending frames, earliest first, until no more than `keep` are
  // left.
  void Output(size_t keep);

  const std::unique_ptr<media::MediaLog> media_log_;
  media::VideoToolboxParameterSetTracker vps_tracker_;
  media::VideoToolboxParameterSetTracker sps_tracker_;
  media::VideoToolboxParameterSetTracker pps_tracker_;
  const VideoToolboxDecodeCB decode_cb_;
  const VideoToolboxOutputCB output_cb_;
  const media::VideoColorSpace container_color_space_;

  // The buffer being decoded, and what's been parsed from it.
  scoped_refptr<media::DecoderBuffer> buffer_;
  std::optional<Frame> frame_;

  Config config_;
  gfx::HDRMetadata hdr_metadata_;

  base::apple::ScopedCFTypeRef<CMFormatDescriptionRef> format_;
  media::VideoToolboxDecompressionSessionMetadata session_metadata_;

  // True until the first frame after a reset is decoded.
  bool first_decode_ = true;
  bool error_ = false;

  std::vector<Pending> pending_;
  uint64_t decode_order_ = 0;
};

}  // namespace fiber

#endif  // FIBER_MEDIA_VIDEO_PASSTHROUGH_DECODER_H_
