#include "fiber/media/hooks/video_toolbox_decoder.h"

#include <utility>

#include "fiber/media/video/h264_passthrough_decoder.h"
#include "fiber/media/video/h265_passthrough_decoder.h"
#include "media/base/media_log.h"

namespace fiber {

std::unique_ptr<media::AcceleratedVideoDecoder> CreateVideoToolboxDecoder(
    media::VideoCodec codec,
    std::unique_ptr<media::MediaLog> media_log,
    VideoToolboxDecodeCB decode_cb,
    VideoToolboxOutputCB output_cb,
    const media::VideoColorSpace& container_color_space) {
  switch (codec) {
    case media::VideoCodec::kH264:
      return std::make_unique<H264PassthroughDecoder>(
          std::move(media_log), std::move(decode_cb), std::move(output_cb),
          container_color_space);
    case media::VideoCodec::kHEVC:
      return std::make_unique<H265PassthroughDecoder>(
          std::move(media_log), std::move(decode_cb), std::move(output_cb),
          container_color_space);
    default:
      return nullptr;
  }
}

}  // namespace fiber
