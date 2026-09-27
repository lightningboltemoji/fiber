#ifndef FIBER_MEDIA_HOOKS_WEB_AUDIO_DECODER_H_
#define FIBER_MEDIA_HOOKS_WEB_AUDIO_DECODER_H_

#include <memory>

namespace media {
class AudioDecoder;
class AudioDecoderConfig;
}  // namespace media

// Fiber decodes AAC for Web Audio's decodeAudioData with AudioToolbox, in the
// GPU process, as media playback does (see
// patches/chromium/content-renderer-media-audio_decoder.cc.patch).
namespace fiber {

// The decoder media::AudioFileReader uses for `config` ahead of ffmpeg's: the
// GPU process's, for AAC (see fiber/media/web_audio/gpu_audio_decoder.h). Null
// for anything else, or on a thread that can't wait on the GPU process.
std::unique_ptr<media::AudioDecoder> CreateWebAudioDecoder(
    const media::AudioDecoderConfig& config);

}  // namespace fiber

#endif  // FIBER_MEDIA_HOOKS_WEB_AUDIO_DECODER_H_
