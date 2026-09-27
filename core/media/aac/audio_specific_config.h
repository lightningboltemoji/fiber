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

// The AudioSpecificConfig AudioToolbox decodes a stream with. An AAC-LC
// config that doesn't signal SBR may still carry it (implicit signaling,
// 1.6.5.3), and ADTS never signals it: HE-AAC in MPEG-2 TS (HLS) and internet
// radio arrives that way. Where the core runs at 24 kHz or less, as HE-AAC's
// does, this signals SBR explicitly, and for mono PS too, as Chromium does
// when a codec string says HE-AAC. AudioToolbox then decodes those layers if
// they're there, and upsamples the core if they're not. Anything else comes
// back as it is.
std::vector<uint8_t> AudioToolboxAudioSpecificConfig(
    base::span<const uint8_t> config);

// What AudioToolbox puts out for a stream with AudioSpecificConfig `config`,
// given AudioToolboxAudioSpecificConfig(config): SBR's rate, and two channels
// for PS's mono, as Chromium's MP4 parser reckons them. Nothing where the
// config doesn't say, as when a program config element gives the channels.
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
