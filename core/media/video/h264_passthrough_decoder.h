#ifndef FIBER_MEDIA_VIDEO_H264_PASSTHROUGH_DECODER_H_
#define FIBER_MEDIA_VIDEO_H264_PASSTHROUGH_DECODER_H_

#include <memory>
#include <optional>

#include "base/time/time.h"
#include "fiber/media/video/passthrough_decoder.h"
#include "media/parsers/h264_parser.h"

namespace fiber {

// H.264's side of PassthroughDecoder: SPS and PPS, and where decoding can
// start.
class H264PassthroughDecoder : public PassthroughDecoder {
 public:
  H264PassthroughDecoder(std::unique_ptr<media::MediaLog> media_log,
                         VideoToolboxDecodeCB decode_cb,
                         VideoToolboxOutputCB output_cb,
                         const media::VideoColorSpace& container_color_space);
  ~H264PassthroughDecoder() override;

 private:
  // What the buffer's first slice says about its frame.
  struct Picture {
    // A copy: a parameter set later in the buffer replaces the parser's.
    std::optional<media::H264SPS> sps;
    bool idr = false;
    int frame_num = 0;
    // A recovery point SEI's recovery_frame_cnt (D.2.8).
    std::optional<int> recovery_frame_cnt;
  };

  // PassthroughDecoder:
  ParseResult Parse(const media::DecoderBuffer& buffer, Frame& frame) override;
  base::apple::ScopedCFTypeRef<CMFormatDescriptionRef> CreateFormat(
      const std::vector<const uint8_t*>& parameter_sets,
      const std::vector<size_t>& parameter_set_sizes,
      const Frame& frame) override;
  void OnReset() override;

  // Parses the NAL units of the buffer the parser's on into `frame` and
  // `picture`.
  ParseResult ParseNalus(Frame& frame, Picture& picture);

  // What `sps` says about the frames that use it. False if it's unusable.
  bool ParseConfig(const media::H264SPS& sps, Config& config);

  // What to do with a frame that can't be parsed: skip it while waiting for
  // somewhere to start, and fail after.
  ParseResult Unusable() const {
    return waiting_ ? ParseResult::kSkip : ParseResult::kError;
  }

  media::H264Parser parser_;

  // Waiting for a frame decoding can start at: an IDR frame, or one that
  // carries a recovery point SEI.
  bool waiting_ = true;

  // After starting at a recovery point, the frame_num of the first frame
  // that's whole, which may be a few frames on (D.2.8); frames before it are
  // decoded but not shown. Then that frame's timestamp, which frames that
  // come before it (the ones that refer to frames from before the recovery
  // point) are skipped for, until the first frame after it.
  std::optional<int> recovery_frame_num_;
  std::optional<base::TimeDelta> shown_from_;
};

}  // namespace fiber

#endif  // FIBER_MEDIA_VIDEO_H264_PASSTHROUGH_DECODER_H_
