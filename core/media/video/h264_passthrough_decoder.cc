#include "fiber/media/video/h264_passthrough_decoder.h"

#include <algorithm>
#include <utility>
#include <variant>

#include "media/base/agtm.h"
#include "media/base/media_log.h"
#include "media/parsers/h264_level_limits.h"
#include "third_party/abseil-cpp/absl/functional/overload.h"

namespace fiber {

namespace {

// H.264's largest decoded picture buffer, in frames (A.3.1).
constexpr size_t kMaxDpbFrames = 16;

}  // namespace

H264PassthroughDecoder::H264PassthroughDecoder(
    std::unique_ptr<media::MediaLog> media_log,
    VideoToolboxDecodeCB decode_cb,
    VideoToolboxOutputCB output_cb,
    const media::VideoColorSpace& container_color_space)
    : PassthroughDecoder(std::move(media_log),
                         std::move(decode_cb),
                         std::move(output_cb),
                         container_color_space) {}

H264PassthroughDecoder::~H264PassthroughDecoder() = default;

H264PassthroughDecoder::ParseResult H264PassthroughDecoder::Parse(
    const media::DecoderBuffer& buffer,
    Frame& frame) {
  Picture picture;
  parser_.SetStream(base::span(buffer));
  const ParseResult result = ParseNalus(frame, picture);
  parser_.Reset();
  if (result != ParseResult::kOk) {
    return result;
  }
  if (frame.nalus.empty()) {
    return ParseResult::kSkip;
  }

  // Decoding starts at an IDR frame or a recovery point (D.2.8), as in
  // H264Decoder.
  const bool idr = picture.idr;
  const int frame_num = picture.frame_num;
  const int max_frame_num =
      1 << (picture.sps->log2_max_frame_num_minus4 + 4);
  std::optional<int> recovery_frame_cnt = picture.recovery_frame_cnt;
  if (recovery_frame_cnt && (*recovery_frame_cnt < 0 ||
                             *recovery_frame_cnt >= max_frame_num)) {
    recovery_frame_cnt.reset();
  }
  if (waiting_) {
    if (!idr && !recovery_frame_cnt) {
      return ParseResult::kSkip;
    }
    waiting_ = false;
    if (!idr) {
      recovery_frame_num_ = (*recovery_frame_cnt + frame_num) % max_frame_num;
    }
  }
  if (idr) {
    recovery_frame_num_.reset();
    shown_from_.reset();
  }
  if (recovery_frame_num_) {
    if (frame_num != *recovery_frame_num_) {
      frame.shown = false;
    } else {
      recovery_frame_num_.reset();
      shown_from_ = buffer.timestamp();
    }
  } else if (shown_from_) {
    if (buffer.timestamp() < *shown_from_) {
      return ParseResult::kSkip;
    }
    shown_from_.reset();
  }

  if (!ParseConfig(*picture.sps, frame.config)) {
    return ParseResult::kError;
  }
  frame.session_metadata = {
      // VideoToolbox's software decoder takes what the hardware doesn't:
      // interlaced video, and small frames on Intel. Chromium has ffmpeg's
      // decoder for those; with none, H.264 is as Chromium has HEVC.
      .allow_software_decoding = true,
      .bit_depth = frame.config.bit_depth,
      .chroma_sampling = frame.config.chroma_sampling,
      .visible_rect = frame.config.visible_rect,
  };
  frame.keyframe = idr;
  frame.starts_sequence = idr;
  frame.reset_decoder = !idr;
  return ParseResult::kOk;
}

H264PassthroughDecoder::ParseResult H264PassthroughDecoder::ParseNalus(
    Frame& frame,
    Picture& picture) {
  while (true) {
    media::H264NALU nalu;
    const media::H264Parser::Result result = parser_.AdvanceToNextNALU(&nalu);
    if (result == media::H264Parser::kEOStream) {
      return ParseResult::kOk;
    }
    if (result != media::H264Parser::kOk) {
      return Unusable();
    }

    switch (nalu.nal_unit_type) {
      case media::H264NALU::kSPS: {
        int id;
        if (parser_.ParseSPS(&id) != media::H264Parser::kOk) {
          return Unusable();
        }
        sps_tracker().Process(id, nalu.data);
        break;
      }

      case media::H264NALU::kPPS: {
        int id;
        if (parser_.ParsePPS(&id) != media::H264Parser::kOk) {
          return Unusable();
        }
        pps_tracker().Process(id, nalu.data);
        break;
      }

      case media::H264NALU::kSEIMessage: {
        // As in H264Decoder, an SEI that doesn't parse is ignored.
        media::H264SEI sei;
        if (parser_.ParseSEI(&sei) != media::H264Parser::kOk) {
          break;
        }
        for (const media::H264SEIMessage& message : sei.msgs) {
          std::visit(
              absl::Overload{
                  [&](const media::H264SEIRecoveryPoint& recovery_point) {
                    picture.recovery_frame_cnt =
                        recovery_point.recovery_frame_cnt;
                  },
                  [&](const media::H26xSEIContentLightLevelInfo& info) {
                    hdr_metadata().SetCLLI(info.ToSkHdr());
                  },
                  [&](const media::H26xSEIMasteringDisplayInfo& info) {
                    hdr_metadata().SetMDCV(info.ToSkHdr());
                  },
                  [&](const media::H26xSEIUserDataRegisteredT35& info) {
                    media::SetAgtmFromT35WithCountryCode(
                        hdr_metadata(), info.country_code, info.payload);
                  },
                  [](std::monostate) {}},
              message);
        }
        break;
      }

      case media::H264NALU::kIDRSlice:
      case media::H264NALU::kNonIDRSlice: {
        media::H264SliceHeader slice;
        if (parser_.ParseSliceHeader(nalu, &slice) != media::H264Parser::kOk) {
          return Unusable();
        }
        const media::H264PPS* pps = parser_.GetPPS(slice.pic_parameter_set_id);
        sps_tracker().ReferenceInFrame(pps->seq_parameter_set_id);
        pps_tracker().ReferenceInFrame(pps->pic_parameter_set_id);
        if (frame.nalus.empty()) {
          picture.sps = *parser_.GetSPS(pps->seq_parameter_set_id);
          picture.idr = slice.idr_pic_flag;
          picture.frame_num = slice.frame_num;
        }
        frame.nalus.push_back(nalu.data);
        break;
      }

      default:
        break;
    }
  }
}

bool H264PassthroughDecoder::ParseConfig(const media::H264SPS& sps,
                                         Config& config) {
  const std::optional<gfx::Size> pic_size = sps.GetCodedSize();
  if (!pic_size || pic_size->IsEmpty()) {
    MEDIA_LOG(ERROR, media_log()) << "Invalid H.264 picture size";
    return false;
  }
  config.pic_size = *pic_size;
  config.visible_rect =
      sps.GetVisibleRect().value_or(gfx::Rect(config.pic_size));
  if (!gfx::Rect(config.pic_size).Contains(config.visible_rect)) {
    config.visible_rect = gfx::Rect(config.pic_size);
  }

  config.profile =
      media::H264Parser::ProfileIDCToVideoCodecProfile(sps.profile_idc);
  if (config.profile == media::VIDEO_CODEC_PROFILE_UNKNOWN ||
      sps.bit_depth_luma_minus8 != sps.bit_depth_chroma_minus8) {
    MEDIA_LOG(ERROR, media_log())
        << "Unsupported H.264 profile_idc " << sps.profile_idc;
    return false;
  }
  config.bit_depth = 8 + sps.bit_depth_luma_minus8;
  config.chroma_sampling = sps.GetChromaSampling();

  config.color_space = sps.GetColorSpace().IsSpecified()
                           ? sps.GetColorSpace()
                           : container_color_space();
  if (config.color_space.matrix() == media::VideoColorSpace::MatrixID::RGB &&
      config.chroma_sampling != media::VideoChromaSampling::k444) {
    // Some streams say GBR when they're ordinary YUV, which is only
    // plausible for 4:4:4 (https://crbug.com/341266991).
    config.color_space = media::VideoColorSpace::REC709();
  }

  // The level's MaxDpbFrames (A.3.1), or more if the stream says it needs
  // more.
  int level = sps.level_idc;
  if ((sps.profile_idc == media::H264SPS::kProfileIDCBaseline ||
       sps.profile_idc == media::H264SPS::kProfileIDCMain) &&
      level == 11 && sps.constraint_set3_flag) {
    level = 9;  // Level 1b.
  }
  const size_t max_dpb_mbs =
      media::H264LevelToMaxDpbMbs(static_cast<uint8_t>(level));
  const size_t frame_mbs = static_cast<size_t>(config.pic_size.width() / 16) *
                           static_cast<size_t>(config.pic_size.height() / 16);
  const size_t dpb_size =
      std::max({max_dpb_mbs ? max_dpb_mbs / frame_mbs : kMaxDpbFrames,
                static_cast<size_t>(sps.max_num_ref_frames),
                static_cast<size_t>(sps.max_dec_frame_buffering)});
  config.dpb_size = std::clamp(dpb_size, size_t{1}, kMaxDpbFrames);

  if (sps.vui_parameters_present_flag && sps.bitstream_restriction_flag) {
    config.max_reorder = std::min(
        static_cast<size_t>(sps.max_num_reorder_frames), config.dpb_size);
  } else if (sps.pic_order_cnt_type == 2) {
    // Frames come out in decoding order (8.2.1.3).
    config.max_reorder = 0;
  } else if (sps.constraint_set3_flag &&
             (sps.profile_idc == 44 || sps.profile_idc == 86 ||
              sps.profile_idc == 100 || sps.profile_idc == 110 ||
              sps.profile_idc == 122 || sps.profile_idc == 244)) {
    // Intra-only profiles (E.2.1).
    config.max_reorder = 0;
  } else {
    config.max_reorder = config.dpb_size;
  }
  return true;
}

base::apple::ScopedCFTypeRef<CMFormatDescriptionRef>
H264PassthroughDecoder::CreateFormat(
    const std::vector<const uint8_t*>& parameter_sets,
    const std::vector<size_t>& parameter_set_sizes,
    const Frame& frame) {
  base::apple::ScopedCFTypeRef<CMFormatDescriptionRef> format;
  const OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
      kCFAllocatorDefault, parameter_sets.size(), parameter_sets.data(),
      parameter_set_sizes.data(), media::kNALUHeaderLength,
      format.InitializeInto());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log())
        << "CMVideoFormatDescriptionCreateFromH264ParameterSets()";
    return base::apple::ScopedCFTypeRef<CMFormatDescriptionRef>();
  }
  return format;
}

void H264PassthroughDecoder::OnReset() {
  waiting_ = true;
  recovery_frame_num_.reset();
  shown_from_.reset();
}

}  // namespace fiber
