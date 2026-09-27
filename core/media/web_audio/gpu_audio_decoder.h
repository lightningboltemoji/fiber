#ifndef FIBER_MEDIA_WEB_AUDIO_GPU_AUDIO_DECODER_H_
#define FIBER_MEDIA_WEB_AUDIO_GPU_AUDIO_DECODER_H_

#include <memory>

#include "base/memory/scoped_refptr.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/audio_decoder.h"

namespace fiber {

// An audio decoder in the GPU process (AudioToolbox's, for AAC), for
// media::AudioFileReader, which decodes Web Audio's decodeAudioData on a
// thread pool thread and expects each call's callbacks before it returns.
//
// The GPU process's decoder (a MojoAudioDecoder) runs on a sequence of its
// own, and this waits on it: Initialize() until it's ready, and the flush at
// the end of the stream until everything's decoded. Other Decode() calls
// queue their buffer and return, so the round trips to the GPU process
// overlap with demuxing; the output reaches the reader over later calls, and
// an error at the latest by the flush.
//
// Waiting needs a thread that can block (a thread pool task that may block
// and wait on sync primitives), never the main thread.
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
