#ifndef FIBER_MEDIA_HOOKS_VIDEO_TOOLBOX_DECODER_H_
#define FIBER_MEDIA_HOOKS_VIDEO_TOOLBOX_DECODER_H_

#include <CoreMedia/CoreMedia.h>

#include <memory>

#include "base/apple/scoped_cftyperef.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "media/base/video_codecs.h"
#include "media/gpu/mac/video_toolbox_decompression_metadata.h"

namespace media {
class AcceleratedVideoDecoder;
class CodecPicture;
class MediaLog;
class VideoColorSpace;
}  // namespace media

// Fiber decodes H.264 and HEVC without Chromium's H264Decoder and H265Decoder
// (see patches/chromium/media-gpu-mac-video_toolbox_video_decoder.cc.patch).
namespace fiber {

// VideoToolboxVideoDecoder's callbacks for the decoder it drives: a frame for
// VideoToolbox to decode, and the next frame to show.
using VideoToolboxDecodeCB = base::RepeatingCallback<void(
    base::apple::ScopedCFTypeRef<CMSampleBufferRef>,
    media::VideoToolboxDecompressionSessionMetadata,
    scoped_refptr<media::CodecPicture>)>;
using VideoToolboxOutputCB =
    base::RepeatingCallback<void(scoped_refptr<media::CodecPicture>)>;

// The decoder VideoToolboxVideoDecoder drives for H.264 or HEVC, which leaves
// decoding to VideoToolbox (see fiber/media/video/passthrough_decoder.h).
// Null for other codecs.
std::unique_ptr<media::AcceleratedVideoDecoder> CreateVideoToolboxDecoder(
    media::VideoCodec codec,
    std::unique_ptr<media::MediaLog> media_log,
    VideoToolboxDecodeCB decode_cb,
    VideoToolboxOutputCB output_cb,
    const media::VideoColorSpace& container_color_space);

}  // namespace fiber

#endif  // FIBER_MEDIA_HOOKS_VIDEO_TOOLBOX_DECODER_H_
