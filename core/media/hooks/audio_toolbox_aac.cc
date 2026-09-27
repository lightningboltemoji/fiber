#include "fiber/media/hooks/audio_toolbox_aac.h"

#include <vector>

namespace fiber {

bool AudioToolboxAacFormat(base::span<const uint8_t> esds,
                           AudioStreamBasicDescription* format) {
  // AudioToolbox only takes the low-delay object types (AAC-LD and AAC-ELD)
  // under their own format IDs.
  for (const AudioFormatID format_id :
       {kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_ELD,
        kAudioFormatMPEG4AAC_LD}) {
    AudioFormatInfo info = {};
    info.mASBD.mFormatID = format_id;
    info.mMagicCookie = esds.data();
    info.mMagicCookieSize = esds.size();

    UInt32 size = 0;
    if (AudioFormatGetPropertyInfo(kAudioFormatProperty_FormatList,
                                   sizeof(info), &info, &size) != noErr) {
      continue;
    }
    std::vector<AudioFormatListItem> layers(size /
                                            sizeof(AudioFormatListItem));
    if (layers.empty() ||
        AudioFormatGetProperty(kAudioFormatProperty_FormatList, sizeof(info),
                               &info, &size, layers.data()) != noErr) {
      continue;
    }

    // The list runs from the richest layer (HE-AAC v2, then HE-AAC) down to
    // AAC-LC.
    *format = layers.front().mASBD;
    return format->mFormatID != 0 && format->mFramesPerPacket != 0;
  }
  return false;
}

base::span<const uint8_t> AudioToolboxPacket(base::span<const uint8_t> packet) {
  // An ADTS header starts with a 12-bit syncword and a layer of 0, and gives
  // the frame's length, header included. It's 7 bytes, or 9 with a CRC.
  if (packet.size() < 7 || packet[0] != 0xff || (packet[1] & 0xf6) != 0xf0) {
    return packet;
  }
  const size_t frame_length = ((packet[3] & 0x03u) << 11) |
                              (packet[4] << 3) | (packet[5] >> 5);
  const size_t header_size = (packet[1] & 0x01) ? 7 : 9;
  if (frame_length != packet.size() || header_size >= packet.size()) {
    return packet;
  }
  return packet.subspan(header_size);
}

}  // namespace fiber
