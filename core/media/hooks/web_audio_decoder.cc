#include "fiber/media/hooks/web_audio_decoder.h"

#include "base/task/sequenced_task_runner.h"
#include "fiber/media/web_audio/gpu_audio_decoder.h"
#include "media/base/audio_decoder_config.h"

namespace fiber {

std::unique_ptr<media::AudioDecoder> CreateWebAudioDecoder(
    const media::AudioDecoderConfig& config) {
  if (config.codec() != media::AudioCodec::kAAC) {
    return nullptr;
  }
  // decodeAudioData decodes in a thread pool task, which may wait on the GPU
  // process; such a task has no task runner of its own. A thread that does,
  // like the main thread, mustn't wait.
  if (base::SequencedTaskRunner::HasCurrentDefault()) {
    return nullptr;
  }
  return std::make_unique<GpuAudioDecoder>();
}

}  // namespace fiber
