#include "fiber/media/video/passthrough_decoder.h"

#include <algorithm>
#include <utility>

#include "base/functional/callback.h"
#include "media/base/limits.h"
#include "media/base/media_log.h"

namespace fiber {

PassthroughDecoder::Frame::Frame() = default;
PassthroughDecoder::Frame::~Frame() = default;

PassthroughDecoder::PassthroughDecoder(
    std::unique_ptr<media::MediaLog> media_log,
    VideoToolboxDecodeCB decode_cb,
    VideoToolboxOutputCB output_cb,
    const media::VideoColorSpace& container_color_space)
    : media_log_(std::move(media_log)),
      vps_tracker_("VPS", media_log_.get()),
      sps_tracker_("SPS", media_log_.get()),
      pps_tracker_("PPS", media_log_.get()),
      decode_cb_(std::move(decode_cb)),
      output_cb_(std::move(output_cb)),
      container_color_space_(container_color_space) {}

PassthroughDecoder::~PassthroughDecoder() = default;

void PassthroughDecoder::SetStream(
    int32_t id,
    scoped_refptr<media::DecoderBuffer> decoder_buffer) {
  buffer_ = std::move(decoder_buffer);
  frame_.reset();
}

bool PassthroughDecoder::Flush() {
  Output(0);
  return true;
}

void PassthroughDecoder::Reset() {
  buffer_.reset();
  frame_.reset();
  pending_.clear();

  // VideoToolbox's session is reset too, so it has no parameter sets.
  vps_tracker_.ResetActive();
  sps_tracker_.ResetActive();
  pps_tracker_.ResetActive();
  format_.reset();

  first_decode_ = true;
  error_ = false;
  OnReset();
}

PassthroughDecoder::DecodeResult PassthroughDecoder::Decode() {
  if (error_) {
    return kDecodeError;
  }
  if (!buffer_) {
    return kRanOutOfStreamData;
  }

  if (!frame_) {
    frame_.emplace();
    vps_tracker_.ResetFrame();
    sps_tracker_.ResetFrame();
    pps_tracker_.ResetFrame();
    switch (Parse(*buffer_, *frame_)) {
      case ParseResult::kOk:
        break;
      case ParseResult::kSkip:
        frame_.reset();
        buffer_.reset();
        return kRanOutOfStreamData;
      case ParseResult::kError:
        error_ = true;
        return kDecodeError;
    }

    // A new size, profile, bit depth or chroma sampling is a new
    // configuration, which the client hears about before the frame is
    // decoded. It calls Decode() again to go on.
    const Config& config = frame_->config;
    const bool changed = config.pic_size != config_.pic_size ||
                         config.profile != config_.profile ||
                         config.bit_depth != config_.bit_depth ||
                         config.chroma_sampling != config_.chroma_sampling;
    config_ = config;
    if (changed) {
      return kConfigChange;
    }
  }

  const bool submitted = Submit();
  frame_.reset();
  buffer_.reset();
  if (!submitted) {
    error_ = true;
    return kDecodeError;
  }
  return kRanOutOfStreamData;
}

bool PassthroughDecoder::Submit() {
  const Frame& frame = *frame_;

  if (frame.starts_sequence) {
    Output(0);
  }

  // Parameter sets that changed since VideoToolbox last saw them. A new VPS
  // or SPS, or any change at a keyframe, makes a new format; otherwise they
  // go in-band, ahead of the frame.
  std::vector<base::span<const uint8_t>> nalus;
  if (!vps_tracker_.ExtractForInbandUpdate(nalus) ||
      !sps_tracker_.ExtractForInbandUpdate(nalus)) {
    return false;
  }
  const bool new_sequence_parameters = !nalus.empty();
  if (!pps_tracker_.ExtractForInbandUpdate(nalus)) {
    return false;
  }
  if (!format_ || new_sequence_parameters ||
      (frame.keyframe && !nalus.empty())) {
    nalus.clear();
    std::vector<const uint8_t*> parameter_sets;
    std::vector<size_t> parameter_set_sizes;
    if (!vps_tracker_.ExtractForFormat(parameter_sets, parameter_set_sizes) ||
        !sps_tracker_.ExtractForFormat(parameter_sets, parameter_set_sizes) ||
        !pps_tracker_.ExtractForFormat(parameter_sets, parameter_set_sizes)) {
      return false;
    }
    format_ = CreateFormat(parameter_sets, parameter_set_sizes, frame);
    if (!format_) {
      return false;
    }
    session_metadata_ = frame.session_metadata;
  }
  nalus.insert(nalus.end(), frame.nalus.begin(), frame.nalus.end());

  base::apple::ScopedCFTypeRef<CMSampleBufferRef> sample =
      media::VideoToolboxCreateSampleBufferFromNALUs(nalus, format_.get(),
                                                     media_log_.get());
  if (!sample) {
    return false;
  }
  if (first_decode_ && frame.reset_decoder) {
    // Apple's advice for starting somewhere other than a keyframe, such as an
    // SEI recovery point (https://crbug.com/451536366).
    CMSetAttachment(sample.get(),
                    kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding,
                    kCFBooleanTrue, kCMAttachmentMode_ShouldNotPropagate);
  }
  first_decode_ = false;

  auto picture = base::MakeRefCounted<media::CodecPicture>();
  picture->set_visible_rect(config_.visible_rect);
  picture->set_colorspace(config_.color_space);
  picture->SetDynamicHdrMetadata(hdr_metadata_, buffer_.get());
  decode_cb_.Run(std::move(sample), session_metadata_, picture);

  if (frame.shown) {
    pending_.push_back({buffer_->timestamp(), decode_order_++,
                        std::move(picture)});
    Output(config_.max_reorder);
  }
  return true;
}

void PassthroughDecoder::Output(size_t keep) {
  // In presentation order, which is timestamp order; frames with the same
  // timestamp keep their decoding order.
  while (pending_.size() > keep) {
    auto next = std::ranges::min_element(
        pending_, [](const Pending& a, const Pending& b) {
          return a.timestamp < b.timestamp ||
                 (a.timestamp == b.timestamp &&
                  a.decode_order < b.decode_order);
        });
    scoped_refptr<media::CodecPicture> picture = std::move(next->picture);
    pending_.erase(next);
    output_cb_.Run(std::move(picture));
  }
}

gfx::Size PassthroughDecoder::GetPicSize() const {
  return config_.pic_size;
}

gfx::Rect PassthroughDecoder::GetVisibleRect() const {
  return config_.visible_rect;
}

media::VideoCodecProfile PassthroughDecoder::GetProfile() const {
  return config_.profile;
}

uint8_t PassthroughDecoder::GetBitDepth() const {
  return config_.bit_depth;
}

media::VideoChromaSampling PassthroughDecoder::GetChromaSampling() const {
  return config_.chroma_sampling;
}

media::VideoColorSpace PassthroughDecoder::GetVideoColorSpace() const {
  return config_.color_space;
}

size_t PassthroughDecoder::GetRequiredNumOfPictures() const {
  return GetNumReferenceFrames() + media::limits::kMaxVideoFrames + 1;
}

size_t PassthroughDecoder::GetNumReferenceFrames() const {
  return config_.dpb_size;
}

}  // namespace fiber
