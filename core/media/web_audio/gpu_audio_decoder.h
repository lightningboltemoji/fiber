#ifndef FIBER_MEDIA_WEB_AUDIO_GPU_AUDIO_DECODER_H_
#define FIBER_MEDIA_WEB_AUDIO_GPU_AUDIO_DECODER_H_

#include <memory>

#include "base/memory/scoped_refptr.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/audio_decoder.h"

namespace fiber {

// Decodes in the GPU process for Web Audio's media::AudioFileReader, which
// wants each call's callbacks before it returns. Initialize() and the final
// flush block, so never use it on the main thread; other buffers queue.
class GpuAudioDecoder final : public media::AudioDecoder {
 public:
  GpuAudioDecoder();
  GpuAudioDecoder(const GpuAudioDecoder&) = delete;
  GpuAudioDecoder& operator=(const GpuAudioDecoder&) = delete;
  ~GpuAudioDecoder() override;

  // AudioDecoder:
  media::AudioDecoderType GetDecoderType() const override;
  void Initialize(const media::AudioDecoderConfig& config,
                  media::CdmContext* cdm_context,
                  InitCB init_cb,
                  const OutputCB& output_cb,
                  const media::WaitingCB& waiting_cb) override;
  void Decode(scoped_refptr<media::DecoderBuffer> buffer,
              DecodeCB decode_cb) override;
  void Reset(base::OnceClosure closure) override;

 private:
  class Core;

  // Runs `output_cb_` for what's been decoded so far.
  void Output();

  scoped_refptr<base::SequencedTaskRunner> task_runner_;
  std::unique_ptr<Core, base::OnTaskRunnerDeleter> core_;
  OutputCB output_cb_;
};

}  // namespace fiber

#endif  // FIBER_MEDIA_WEB_AUDIO_GPU_AUDIO_DECODER_H_
