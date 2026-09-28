#ifndef FIBER_MEDIA_AAC_AUDIO_SPECIFIC_CONFIG_H_
#define FIBER_MEDIA_AAC_AUDIO_SPECIFIC_CONFIG_H_

#include <stdint.h>

#include <optional>
#include <vector>

#include "base/containers/span.h"

// AAC's AudioSpecificConfig (ISO 14496-3 1.6.2.1) as Fiber gives it to
// AudioToolbox, in the GPU process, and what AudioToolbox puts out for it,
// which the renderer's ffmpeg demuxer describes.
namespace fiber {

// The AudioSpecificConfig AudioToolbox decodes a stream with. AAC-LC at 24 kHz
// or less may carry SBR implicitly (1.6.5.3), so it gets SBR, and PS for mono,
// signaled; AudioToolbox upsamples the core if absent (.agents/MEDIA.md).
std::vector<uint8_t> AudioToolboxAudioSpecificConfig(
    base::span<const uint8_t> config);

// What AudioToolbox puts out for `config`, once rewritten as above: SBR's rate,
// and two channels for PS's mono, as Chromium's MP4 parser reckons them.
// Nothing where the config doesn't say (a program config element's channels).
struct AudioToolboxOutput {
  int sample_rate = 0;
  int channels = 0;
};
std::optional<AudioToolboxOutput> AudioToolboxOutputFormat(
    base::span<const uint8_t> config);

// The AudioSpecificConfig an ADTS header implies, for demuxers that give
// none (ffmpeg's): `object_type` as ADTS numbers it (1 for AAC-LC), the
// sample rate and the channel count. Empty if they don't fit.
std::vector<uint8_t> AdtsAudioSpecificConfig(int object_type,
                                             int sample_rate,
                                             int channels);

// The same, from the header an ADTS frame starts with. Empty if it doesn't
// start with one, or its config doesn't fit one (a program config element).
std::vector<uint8_t> AdtsHeaderAudioSpecificConfig(
    base::span<const uint8_t> frame);

}  // namespace fiber

#endif  // FIBER_MEDIA_AAC_AUDIO_SPECIFIC_CONFIG_H_
