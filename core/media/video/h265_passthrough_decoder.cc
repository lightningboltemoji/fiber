#include "fiber/media/video/h265_passthrough_decoder.h"

#include <algorithm>
#include <utility>
#include <variant>

#include "media/base/agtm.h"
#include "media/base/media_log.h"
#include "media/gpu/mac/vt_config_util.h"
#include "third_party/abseil-cpp/absl/functional/overload.h"

namespace fiber {

namespace {

// Slice segments, the NAL unit types H265Decoder decodes.
bool IsSlice(int nal_unit_type) {
  return (nal_unit_type >= media::H265NALU::TRAIL_N &&
          nal_unit_type <= media::H265NALU::RASL_R) ||
         (nal_unit_type >= media::H265NALU::BLA_W_LP &&
          nal_unit_type <= media::H265NALU::CRA_NUT);
}

}  // namespace

H265PassthroughDecoder::Picture::Picture() = default;
H265PassthroughDecoder::Picture::~Picture() = default;

H265PassthroughDecoder::H265PassthroughDecoder(
    std::unique_ptr<media::MediaLog> media_log,
    VideoToolboxDecodeCB decode_cb,
    VideoToolboxOutputCB output_cb,
    const media::VideoColorSpace& container_color_space)
    : PassthroughDecoder(std::move(media_log),
                         std::move(decode_cb),
                         std::move(output_cb),
                         container_color_space) {}

H265PassthroughDecoder::~H265PassthroughDecoder() = default;

H265PassthroughDecoder::ParseResult H265PassthroughDecoder::Parse(
    const media::DecoderBuffer& buffer,
    Frame& frame) {
  // An end of sequence ends the frame before this one.
  if (end_of_sequence_) {
    end_of_sequence_ = false;
    waiting_ = true;
  }

  std::unique_ptr<Picture> picture;
  parser_.SetStream(base::span(buffer));
  const ParseResult result = ParseNalus(frame, picture);
  parser_.Reset();
  if (result != ParseResult::kOk) {
    return result;
  }
  if (!picture) {
    return ParseResult::kSkip;
  }

  // Decoding starts at an IRAP frame, and skips the RASL frames that follow
  // it (8.1.3), as in H265Decoder.
  const media::H265SliceHeader& slice = picture->slice;
  bool starts_sequence = false;
  if (slice.irap_pic) {
    // IDR and BLA frames start a coded video sequence, and so does a CRA
    // frame where decoding starts.
    skip_rasl_ = waiting_ || slice.nal_unit_type <= media::H265NALU::IDR_N_LP;
    starts_sequence = skip_rasl_;
    waiting_ = false;
  } else if (waiting_) {
    return ParseResult::kSkip;
  }
  if (skip_rasl_ && (slice.nal_unit_type == media::H265NALU::RASL_N ||
                     slice.nal_unit_type == media::H265NALU::RASL_R)) {
    return ParseResult::kSkip;
  }

  if (!ParseConfig(*picture->sps, frame.config)) {
    return ParseResult::kError;
  }
  frame.session_metadata = {
      // As in Chromium: VideoToolbox's software decoder handles what the
      // hardware doesn't, such as small frames.
      .allow_software_decoding = true,
      .bit_depth = frame.config.bit_depth,
      .chroma_sampling = frame.config.chroma_sampling,
      .has_alpha =
          alpha_vps_ids_.contains(picture->sps->sps_video_parameter_set_id),
      .visible_rect = frame.config.visible_rect,
  };
  frame.keyframe = slice.irap_pic;
  frame.starts_sequence = starts_sequence;
  frame.shown = slice.pic_output_flag;
  return ParseResult::kOk;
}

H265PassthroughDecoder::ParseResult H265PassthroughDecoder::ParseNalus(
    Frame& frame,
    std::unique_ptr<Picture>& picture) {
  while (true) {
    media::H265NALU nalu;
    const media::H265Parser::Result result = parser_.AdvanceToNextNALU(&nalu);
    if (result == media::H265Parser::kEOStream) {
      return ParseResult::kOk;
    }
    if (result != media::H265Parser::kOk) {
      return Unusable();
    }

    // Of the layers above the base layer, only an auxiliary alpha layer,
    // which VideoToolbox decodes along with the base layer.
    if (nalu.nuh_layer_id && nalu.nuh_layer_id != aux_alpha_layer_id_) {
      continue;
    }

    switch (nalu.nal_unit_type) {
      case media::H265NALU::VPS_NUT: {
        if (nalu.nuh_layer_id) {
          break;
        }
        int id;
        if (parser_.ParseVPS(&id) != media::H265Parser::kOk) {
          return Unusable();
        }
        vps_tracker().Process(id, nalu.data);
        aux_alpha_layer_id_ = parser_.GetVPS(id)->aux_alpha_layer_id;
        if (aux_alpha_layer_id_) {
          alpha_vps_ids_.insert(id);
        } else {
          alpha_vps_ids_.erase(id);
        }
        break;
      }

      case media::H265NALU::SPS_NUT: {
        int id;
        if (parser_.ParseSPS(&id) != media::H265Parser::kOk) {
          return Unusable();
        }
        sps_tracker().Process(id, nalu.data);
        break;
      }

      case media::H265NALU::PPS_NUT: {
        int id;
        if (parser_.ParsePPS(nalu, &id) != media::H265Parser::kOk) {
          return Unusable();
        }
        pps_tracker().Process(id, nalu.data);
        break;
      }

      case media::H265NALU::EOS_NUT:
      case media::H265NALU::EOB_NUT:
        if (picture) {
          end_of_sequence_ = true;
        } else {
          waiting_ = true;
        }
        break;

      case media::H265NALU::PREFIX_SEI_NUT: {
        if (nalu.nuh_layer_id) {
          break;
        }
        // As in H265Decoder, an SEI that doesn't parse is ignored.
        media::H265SEI sei;
        if (parser_.ParseSEI(&sei) != media::H265Parser::kOk) {
          break;
        }
        for (const media::H265SEIMessage& message : sei.msgs) {
          std::visit(
              absl::Overload{
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
                  [](const media::H265SEIAlphaChannelInfo&) {},
                  [](std::monostate) {}},
              message);
        }
        break;
      }

      default: {
        if (!IsSlice(nalu.nal_unit_type)) {
          break;
        }
        int pps_id;
        media::H265Parser::Result slice_result;
        if (!picture && !nalu.nuh_layer_id) {
          // The first slice segment of the base layer's picture, whose
          // header says what the frame is.
          picture = std::make_unique<Picture>();
          slice_result =
              parser_.ParseSliceHeader(nalu, &picture->slice, nullptr);
          if (slice_result == media::H265Parser::kOk &&
              !picture->slice.first_slice_segment_in_pic_flag) {
            slice_result = media::H265Parser::kInvalidStream;
          }
          pps_id = picture->slice.slice_pic_parameter_set_id;
        } else {
          slice_result =
              parser_.ParseSliceHeaderForPictureParameterSets(nalu, &pps_id);
        }
        if (slice_result == media::H265Parser::kMissingParameterSet ||
            (slice_result == media::H265Parser::kOk &&
             !ReferenceParameterSets(pps_id))) {
          if (nalu.nuh_layer_id) {
            // As in H265Decoder: without the alpha layer's parameter sets,
            // the frame is decoded without its alpha.
            break;
          }
          // Wait for the parameter sets, and an IRAP frame to start at.
          waiting_ = true;
          return ParseResult::kSkip;
        }
        if (slice_result != media::H265Parser::kOk) {
          return Unusable();
        }
        if (picture && !picture->sps && !nalu.nuh_layer_id) {
          picture->sps =
              *parser_.GetSPS(parser_.GetPPS(pps_id)->pps_seq_parameter_set_id);
        }
        frame.nalus.push_back(nalu.data);
        break;
      }
    }
  }
}

bool H265PassthroughDecoder::ReferenceParameterSets(int pps_id) {
  const media::H265PPS* pps = parser_.GetPPS(pps_id);
  const media::H265SPS* sps =
      pps ? parser_.GetSPS(pps->pps_seq_parameter_set_id) : nullptr;
  if (!sps) {
    return false;
  }
  vps_tracker().ReferenceInFrame(sps->sps_video_parameter_set_id);
  sps_tracker().ReferenceInFrame(sps->sps_seq_parameter_set_id);
  pps_tracker().ReferenceInFrame(pps->pps_pic_parameter_set_id);
  return true;
}

bool H265PassthroughDecoder::ParseConfig(const media::H265SPS& sps,
                                         Config& config) {
  // The parser checks that the visible rect is in the picture and not empty.
  config.pic_size = sps.GetCodedSize();
  config.visible_rect = sps.GetVisibleRect();

  config.profile = media::H265Parser::ProfileIDCToVideoCodecProfile(
      sps.profile_tier_level.general_profile_idc);
  if (config.profile == media::VIDEO_CODEC_PROFILE_UNKNOWN ||
      sps.bit_depth_y != sps.bit_depth_c) {
    MEDIA_LOG(ERROR, media_log())
        << "Unsupported HEVC general_profile_idc "
        << static_cast<int>(sps.profile_tier_level.general_profile_idc);
    return false;
  }
  config.bit_depth = sps.bit_depth_y;
  config.chroma_sampling = sps.GetChromaSampling();

  config.color_space = sps.GetColorSpace().IsSpecified()
                           ? sps.GetColorSpace()
                           : container_color_space();
  if (config.color_space.matrix() == media::VideoColorSpace::MatrixID::RGB &&
      config.chroma_sampling != media::VideoChromaSampling::k444) {
    // Some streams say GBR when they're ordinary YUV, which is only
    // plausible for 4:4:4 (https://crbug.com/342003180).
    config.color_space = media::VideoColorSpace::REC709();
  }

  config.dpb_size = sps.max_dpb_size;
  config.max_reorder =
      std::min(static_cast<size_t>(
                   sps.sps_max_num_reorder_pics[sps.sps_max_sub_layers_minus1]),
               config.dpb_size);
  return true;
}

base::apple::ScopedCFTypeRef<CMFormatDescriptionRef>
H265PassthroughDecoder::CreateFormat(
    const std::vector<const uint8_t*>& parameter_sets,
    const std::vector<size_t>& parameter_set_sizes,
    const Frame& frame) {
  // With a color space, VideoToolbox makes images in it where the stream
  // doesn't say, rather than assuming BT.709. The profile doesn't matter
  // here.
  base::apple::ScopedCFTypeRef<CFDictionaryRef> extensions;
  if (frame.config.color_space.IsSpecified()) {
    extensions = media::CreateFormatExtensions(
        kCMVideoCodecType_HEVC, media::HEVCPROFILE_MAIN, frame.config.bit_depth,
        frame.config.color_space, std::nullopt);
  }

  base::apple::ScopedCFTypeRef<CMFormatDescriptionRef> format;
  const OSStatus status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
      kCFAllocatorDefault, parameter_sets.size(), parameter_sets.data(),
      parameter_set_sizes.data(), media::kNALUHeaderLength, extensions.get(),
      format.InitializeInto());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log())
        << "CMVideoFormatDescriptionCreateFromHEVCParameterSets()";
    return base::apple::ScopedCFTypeRef<CMFormatDescriptionRef>();
  }
  return format;
}

void H265PassthroughDecoder::OnReset() {
  waiting_ = true;
  end_of_sequence_ = false;
}

}  // namespace fiber
