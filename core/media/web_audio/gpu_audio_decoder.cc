#include "fiber/media/web_audio/gpu_audio_decoder.h"

#include <utility>
#include <vector>

#include "base/containers/circular_deque.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "base/synchronization/condition_variable.h"
#include "base/synchronization/lock.h"
#include "base/task/thread_pool.h"
#include "base/thread_annotations.h"
#include "media/base/audio_buffer.h"
#include "media/base/decoder_buffer.h"
#include "media/base/decoder_status.h"
#include "media/base/media_util.h"
#include "media/mojo/clients/mojo_audio_decoder.h"
#include "media/mojo/mojom/interface_factory.mojom.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "third_party/blink/public/common/thread_safe_browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/platform.h"

namespace fiber {

// The GPU process's decoder, on its sequence. What's under `lock_` is also
// read by the thread that waits on it.
class GpuAudioDecoder::Core {
 public:
  explicit Core(scoped_refptr<base::SequencedTaskRunner> task_runner)
      : task_runner_(std::move(task_runner)) {}
  Core(const Core&) = delete;
  Core& operator=(const Core&) = delete;
  ~Core() = default;

  // Any thread. Counts a call that's about to be posted: false if the decoder
  // has failed, and there's no point.
  bool Begin() {
    base::AutoLock lock(lock_);
    if (!status_.is_ok()) {
      return false;
    }
    ++pending_;
    return true;
  }

  // Any thread. Waits for every call posted to finish, or for one to fail.
  media::DecoderStatus Wait() {
    base::AutoLock lock(lock_);
    while (pending_ && status_.is_ok()) {
      idle_.Wait();
    }
    return status_;
  }

  // Any thread.
  media::DecoderStatus status() {
    base::AutoLock lock(lock_);
    return status_;
  }

  // Any thread. What's been decoded since the last call.
  std::vector<scoped_refptr<media::AudioBuffer>> TakeOutputs() {
    base::AutoLock lock(lock_);
    return std::exchange(outputs_, {});
  }

  // On the sequence, each posted after Begin().
  void Initialize(const media::AudioDecoderConfig& config) {
    mojo::PendingRemote<media::mojom::InterfaceFactory> interface_factory;
    blink::Platform::Current()->GetBrowserInterfaceBroker()->GetInterface(
        interface_factory.InitWithNewPipeAndPassReceiver());
    interface_factory_.Bind(std::move(interface_factory));
    mojo::PendingRemote<media::mojom::AudioDecoder> decoder;
    interface_factory_->CreateAudioDecoder(
        decoder.InitWithNewPipeAndPassReceiver());
    decoder_ = std::make_unique<media::MojoAudioDecoder>(
        task_runner_, &media_log_, std::move(decoder));
    decoder_->Initialize(
        config, /*cdm_context=*/nullptr,
        base::BindOnce(&Core::Done, weak_factory_.GetWeakPtr()),
        base::BindRepeating(&Core::OnOutput, weak_factory_.GetWeakPtr()),
        base::DoNothing());
  }

  void Decode(scoped_refptr<media::DecoderBuffer> buffer) {
    // MojoAudioDecoder takes one at a time.
    queue_.push_back(std::move(buffer));
    if (!decoding_) {
      DecodeNext();
    }
  }

  void Reset() {
    decoder_->Reset(base::BindOnce(&Core::Done, weak_factory_.GetWeakPtr(),
                                   media::DecoderStatus::Codes::kOk));
  }

 private:
  void DecodeNext() {
    decoding_ = true;
    scoped_refptr<media::DecoderBuffer> buffer = std::move(queue_.front());
    queue_.pop_front();
    decoder_->Decode(std::move(buffer), base::BindOnce(&Core::OnDecoded,
                                                       weak_factory_.GetWeakPtr()));
  }

  void OnDecoded(media::DecoderStatus status) {
    decoding_ = false;
    if (!status.is_ok()) {
      queue_.clear();
    }
    Done(std::move(status));
    if (!queue_.empty()) {
      DecodeNext();
    }
  }

  void OnOutput(scoped_refptr<media::AudioBuffer> buffer) {
    base::AutoLock lock(lock_);
    outputs_.push_back(std::move(buffer));
  }

  // A posted call finished.
  void Done(media::DecoderStatus status) {
    base::AutoLock lock(lock_);
    --pending_;
    if (status_.is_ok() && !status.is_ok()) {
      status_ = std::move(status);
    }
    idle_.Broadcast();
  }

  const scoped_refptr<base::SequencedTaskRunner> task_runner_;
  media::NullMediaLog media_log_;
  mojo::Remote<media::mojom::InterfaceFactory> interface_factory_;
  std::unique_ptr<media::MojoAudioDecoder> decoder_;
  base::circular_deque<scoped_refptr<media::DecoderBuffer>> queue_;
  bool decoding_ = false;

  base::Lock lock_;
  base::ConditionVariable idle_{&lock_};
  int pending_ GUARDED_BY(lock_) = 0;
  media::DecoderStatus status_ GUARDED_BY(lock_) =
      media::DecoderStatus::Codes::kOk;
  std::vector<scoped_refptr<media::AudioBuffer>> outputs_ GUARDED_BY(lock_);

  base::WeakPtrFactory<Core> weak_factory_{this};
};

GpuAudioDecoder::GpuAudioDecoder()
    : task_runner_(base::ThreadPool::CreateSequencedTaskRunner({})),
      core_(new Core(task_runner_), base::OnTaskRunnerDeleter(task_runner_)) {}

GpuAudioDecoder::~GpuAudioDecoder() = default;

media::AudioDecoderType GpuAudioDecoder::GetDecoderType() const {
  return media::AudioDecoderType::kMojo;
}

void GpuAudioDecoder::Initialize(const media::AudioDecoderConfig& config,
                                 media::CdmContext* cdm_context,
                                 InitCB init_cb,
                                 const OutputCB& output_cb,
                                 const media::WaitingCB& waiting_cb) {
  output_cb_ = output_cb;
  // `core_` is deleted on its sequence after anything posted to it runs.
  if (core_->Begin()) {
    task_runner_->PostTask(FROM_HERE,
                           base::BindOnce(&Core::Initialize,
                                          base::Unretained(core_.get()), config));
  }
  std::move(init_cb).Run(core_->Wait());
}

void GpuAudioDecoder::Decode(scoped_refptr<media::DecoderBuffer> buffer,
                             DecodeCB decode_cb) {
  const bool end_of_stream = buffer->end_of_stream();
  if (core_->Begin()) {
    task_runner_->PostTask(
        FROM_HERE, base::BindOnce(&Core::Decode, base::Unretained(core_.get()),
                                  std::move(buffer)));
  }
  const media::DecoderStatus status =
      end_of_stream ? core_->Wait() : core_->status();
  Output();
  std::move(decode_cb).Run(status);
}

void GpuAudioDecoder::Reset(base::OnceClosure closure) {
  core_->Wait();
  if (core_->Begin()) {
    task_runner_->PostTask(
        FROM_HERE, base::BindOnce(&Core::Reset, base::Unretained(core_.get())));
    core_->Wait();
  }
  core_->TakeOutputs();
  std::move(closure).Run();
}

void GpuAudioDecoder::Output() {
  for (scoped_refptr<media::AudioBuffer>& buffer : core_->TakeOutputs()) {
    output_cb_.Run(std::move(buffer));
  }
}

}  // namespace fiber
