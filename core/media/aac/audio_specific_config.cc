#include "fiber/media/aac/audio_specific_config.h"

#include <algorithm>
#include <array>
#include <iterator>
#include <optional>
#include <utility>

#include "base/memory/raw_span.h"

namespace fiber {

namespace {

constexpr int kAacLc = 2;
constexpr int kSbr = 5;
constexpr int kPs = 29;

// Sampling frequencies by index (1.6.3.4).
constexpr std::array kSampleRates = {96000, 88200, 64000, 48000, 44100,
                                     32000, 24000, 22050, 16000, 12000,
                                     11025, 8000,  7350};

// HE-AAC's core runs at half the output rate, which is 48 kHz at most.
constexpr int kMaxCoreRate = 24000;

// Signal SBR, and then PS, backward-compatibly, after the GASpecificConfig
// (1.6.5.2).
constexpr uint32_t kSyncExtensionType = 0x2b7;
constexpr uint32_t kPsSyncExtensionType = 0x548;

class BitReader {
 public:
  explicit BitReader(base::span<const uint8_t> data) : data_(data) {}

  bool Read(size_t bits, uint32_t* out) {
    if (bits > remaining()) {
      return false;
    }
    *out = 0;
    for (; bits; --bits, ++position_) {
      *out = (*out << 1) | ((data_[position_ / 8] >> (7 - position_ % 8)) & 1);
    }
    return true;
  }

  size_t remaining() const { return data_.size() * 8 - position_; }

 private:
  base::raw_span<const uint8_t> data_;
  size_t position_ = 0;
};

class BitWriter {
 public:
  void Write(uint32_t value, size_t bits) {
    for (; bits; --bits, ++position_) {
      if (position_ % 8 == 0) {
        bytes_.push_back(0);
      }
      bytes_.back() |= ((value >> (bits - 1)) & 1) << (7 - position_ % 8);
    }
  }

  std::vector<uint8_t> Take() { return std::move(bytes_); }

 private:
  std::vector<uint8_t> bytes_;
  size_t position_ = 0;
};

// A sampling frequency: by index, or given in full after the escape index.
std::optional<int> ReadSampleRate(BitReader& reader) {
  uint32_t index, rate;
  if (!reader.Read(4, &index)) {
    return std::nullopt;
  }
  if (index == 0xf) {
    return reader.Read(24, &rate) ? std::optional<int>(rate) : std::nullopt;
  }
  return index < kSampleRates.size() ? std::optional<int>(kSampleRates[index])
                                     : std::nullopt;
}

std::optional<uint32_t> SampleRateIndex(int rate) {
  const auto it = std::ranges::find(kSampleRates, rate);
  if (it == kSampleRates.end()) {
    return std::nullopt;
  }
  return std::distance(kSampleRates.begin(), it);
}

}  // namespace

std::vector<uint8_t> AudioToolboxAudioSpecificConfig(
    base::span<const uint8_t> config) {
  const std::vector<uint8_t> as_is(config.begin(), config.end());

  // AAC-LC, with a sampling frequency index and a channel configuration.
  BitReader reader(config);
  uint32_t object_type, frequency_index, channels;
  if (!reader.Read(5, &object_type) || object_type != kAacLc ||
      !reader.Read(4, &frequency_index) ||
      frequency_index >= kSampleRates.size() || !reader.Read(4, &channels) ||
      channels == 0) {
    return as_is;
  }

  // Its GASpecificConfig (4.4.1): frameLengthFlag, dependsOnCoreCoder and
  // extensionFlag, which are zero but for the frame length in anything but
  // a scalable or error resilient stream.
  uint32_t frame_length, depends_on_core_coder, extension;
  if (!reader.Read(1, &frame_length) ||
      !reader.Read(1, &depends_on_core_coder) || depends_on_core_coder ||
      !reader.Read(1, &extension) || extension) {
    return as_is;
  }

  // Signaled backward-compatibly, SBR is explicit already.
  uint32_t sync_extension;
  if (reader.remaining() >= 11 && reader.Read(11, &sync_extension) &&
      sync_extension == kSyncExtensionType) {
    return as_is;
  }

  const int core_rate = kSampleRates[frequency_index];
  const std::optional<uint32_t> extension_frequency_index =
      SampleRateIndex(2 * core_rate);
  if (core_rate > kMaxCoreRate || !extension_frequency_index) {
    return as_is;
  }

  // Signaled hierarchically (1.6.5.2): SBR, or PS for mono, then the core.
  BitWriter writer;
  writer.Write(channels == 1 ? kPs : kSbr, 5);
  writer.Write(frequency_index, 4);
  writer.Write(channels, 4);
  writer.Write(*extension_frequency_index, 4);
  writer.Write(kAacLc, 5);
  writer.Write(frame_length, 1);
  writer.Write(0, 2);
  return writer.Take();
}

std::optional<AudioToolboxOutput> AudioToolboxOutputFormat(
    base::span<const uint8_t> config) {
  const std::vector<uint8_t> audio_toolbox_config =
      AudioToolboxAudioSpecificConfig(config);
  BitReader reader(audio_toolbox_config);
  uint32_t object_type, channel_configuration;
  if (!reader.Read(5, &object_type)) {
    return std::nullopt;
  }
  if (object_type == 31) {
    // Escaped: 32 and up (1.6.2.1).
    uint32_t escaped;
    if (!reader.Read(6, &escaped)) {
      return std::nullopt;
    }
    object_type = 32 + escaped;
  }
  std::optional<int> sample_rate = ReadSampleRate(reader);
  if (!sample_rate || !reader.Read(4, &channel_configuration) ||
      channel_configuration == 0) {
    return std::nullopt;
  }
  // Channel configurations 1 to 6 have as many channels; 7 has eight.
  AudioToolboxOutput output = {
      .sample_rate = *sample_rate,
      .channels = channel_configuration == 7 ? 8
                                             : static_cast<int>(
                                                   channel_configuration)};
  bool ps = false;

  if (object_type == kSbr || object_type == kPs) {
    // Signaled hierarchically: SBR's rate comes next.
    sample_rate = ReadSampleRate(reader);
    if (!sample_rate) {
      return std::nullopt;
    }
    output.sample_rate = *sample_rate;
    ps = object_type == kPs;
  } else if (object_type == kAacLc) {
    // Or backward-compatibly, after the GASpecificConfig.
    uint32_t frame_length, depends_on_core_coder, extension, sync_extension,
        extension_object_type, sbr, ps_sync_extension, ps_present;
    if (reader.Read(1, &frame_length) &&
        reader.Read(1, &depends_on_core_coder) && !depends_on_core_coder &&
        reader.Read(1, &extension) && !extension && reader.remaining() >= 16 &&
        reader.Read(11, &sync_extension) &&
        sync_extension == kSyncExtensionType &&
        reader.Read(5, &extension_object_type) &&
        extension_object_type == kSbr && reader.Read(1, &sbr) && sbr) {
      sample_rate = ReadSampleRate(reader);
      if (!sample_rate) {
        return std::nullopt;
      }
      output.sample_rate = *sample_rate;
      ps = reader.remaining() >= 12 && reader.Read(11, &ps_sync_extension) &&
           ps_sync_extension == kPsSyncExtensionType &&
           reader.Read(1, &ps_present) && ps_present;
    }
  }

  if (ps && output.channels == 1) {
    output.channels = 2;
  }
  return output;
}

std::vector<uint8_t> AdtsAudioSpecificConfig(int object_type,
                                             int sample_rate,
                                             int channels) {
  // ADTS numbers object types from 0 (1.A.2.2.1), and its channel
  // configurations run to 7, which is eight channels.
  const std::optional<uint32_t> frequency_index = SampleRateIndex(sample_rate);
  if (object_type < 0 || object_type > 3 || !frequency_index || channels < 1 ||
      channels > 8 || channels == 7) {
    return {};
  }
  BitWriter writer;
  writer.Write(object_type + 1, 5);
  writer.Write(*frequency_index, 4);
  writer.Write(channels == 8 ? 7 : channels, 4);
  writer.Write(0, 3);
  return writer.Take();
}

std::vector<uint8_t> AdtsHeaderAudioSpecificConfig(
    base::span<const uint8_t> frame) {
  // The fixed header (1.A.2.2.1): syncword, ID, layer (0, unlike MPEG
  // audio's), protection_absent, then what the config needs.
  BitReader reader(frame);
  uint32_t syncword, id, layer, protection_absent, profile, frequency_index,
      private_bit, channel_configuration;
  if (!reader.Read(12, &syncword) || syncword != 0xfff ||
      !reader.Read(1, &id) || !reader.Read(2, &layer) || layer != 0 ||
      !reader.Read(1, &protection_absent) || !reader.Read(2, &profile) ||
      !reader.Read(4, &frequency_index) ||
      frequency_index >= kSampleRates.size() ||
      !reader.Read(1, &private_bit) || !reader.Read(3, &channel_configuration)) {
    return {};
  }
  return AdtsAudioSpecificConfig(
      static_cast<int>(profile), kSampleRates[frequency_index],
      channel_configuration == 7 ? 8
                                 : static_cast<int>(channel_configuration));
}

}  // namespace fiber
