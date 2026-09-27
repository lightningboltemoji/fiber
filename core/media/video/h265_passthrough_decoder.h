#ifndef FIBER_MEDIA_VIDEO_H265_PASSTHROUGH_DECODER_H_
#define FIBER_MEDIA_VIDEO_H265_PASSTHROUGH_DECODER_H_

#include <memory>
#include <optional>

#include "base/containers/flat_set.h"
#include "fiber/media/video/passthrough_decoder.h"
#include "media/parsers/h265_parser.h"

namespace fiber {

// HEVC's side of PassthroughDecoder: VPS, SPS and PPS, where decoding can
// start, and Apple's HEVC with alpha, whose alpha is an auxiliary layer.
class H265PassthroughDecoder : public PassthroughDecoder {
 public:
  H265PassthroughDecoder(std::unique_ptr<media::MediaLog> media_log,
                         VideoToolboxDecodeCB decode_cb,
                         VideoToolboxOutputCB output_cb,
                         const media::VideoColorSpace& container_color_space);
  ~H265PassthroughDecoder() override;

 private:
  // The first slice segment's picture: its parameter sets, and its slice
  // header.
  struct Picture {
    Picture();
    ~Picture();

    // A copy: a parameter set later in the buffer replaces the parser's.
    std::optional<media::H265SPS> sps;
    media::H265SliceHeader slice;
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
  ParseResult ParseNalus(Frame& frame, std::unique_ptr<Picture>& picture);

  // Records that the frame uses the parameter sets `pps_id` refers to. False
  // if they're missing.
  bool ReferenceParameterSets(int pps_id);

  // What `sps` says about the frames that use it. False if it's unusable.
  bool ParseConfig(const media::H265SPS& sps, Config& config);

  // What to do with a frame that can't be parsed: skip it while waiting for
  // somewhere to start, and fail after.
  ParseResult Unusable() const {
    return waiting_ ? ParseResult::kSkip : ParseResult::kError;
  }

  media::H265Parser parser_;

  // Waiting for a frame decoding can start at (an IRAP frame): after a reset,
  // an end of sequence, or missing parameter sets.
  bool waiting_ = true;
  // After an end of sequence NAL unit, which ends the buffer's frame.
  bool end_of_sequence_ = false;

  // NoRaslOutputFlag (8.1.3) of the last IRAP frame: the RASL frames that
  // follow it refer to frames from before it, which the decoder doesn't have
  // when that's where decoding started. VideoToolbox fails on them, so
  // they're skipped.
  bool skip_rasl_ = true;

  // The auxiliary alpha layer the latest VPS describes (0 for none), and the
  // VPSs that describe one.
  int aux_alpha_layer_id_ = 0;
  base::flat_set<int> alpha_vps_ids_;
};

}  // namespace fiber

#endif  // FIBER_MEDIA_VIDEO_H265_PASSTHROUGH_DECODER_H_
