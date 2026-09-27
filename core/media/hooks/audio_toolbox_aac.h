#ifndef FIBER_MEDIA_HOOKS_AUDIO_TOOLBOX_AAC_H_
#define FIBER_MEDIA_HOOKS_AUDIO_TOOLBOX_AAC_H_

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>

#include "base/containers/span.h"

// Fiber decodes all AAC with AudioToolbox, not just the xHE-AAC Chromium's
// AudioToolboxAudioDecoder takes (see patches/chromium/
// media-filters-mac-audio_toolbox_audio_decoder.cc.patch).
namespace fiber {

// The format AudioToolbox decodes an AAC stream in, given its `esds`: the
// richest layer the stream carries. Asked for the format an esds describes,
// AudioToolbox answers with an HE-AAC stream's AAC-LC core, at half the sample
// rate, and decoding that drops what the SBR layer adds (and HE-AAC v2's
// stereo). False if AudioToolbox can't decode the stream.
bool AudioToolboxAacFormat(base::span<const uint8_t> esds,
                           AudioStreamBasicDescription* format);

// The part of `packet` AudioToolbox decodes: an AAC frame without the ADTS
// header that MPEG-2 TS carries and Chromium's MP4 parser adds for ffmpeg.
// Anything without an ADTS header comes back as it is.
base::span<const uint8_t> AudioToolboxPacket(base::span<const uint8_t> packet);

}  // namespace fiber

#endif  // FIBER_MEDIA_HOOKS_AUDIO_TOOLBOX_AAC_H_
