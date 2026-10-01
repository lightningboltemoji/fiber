#include "fiber/browser/hooks/crash_reporter.h"

#include <pthread.h>
#include <sys/qos.h>

#include <memory>
#include <utility>

#include "base/functional/callback.h"

namespace fiber {

namespace {

pthread_t g_thread;
bool g_started = false;

void* Run(void* context) {
  std::unique_ptr<base::OnceClosure> start(
      static_cast<base::OnceClosure*>(context));
  std::move(*start).Run();
  return nullptr;
}

}  // namespace

void StartCrashReporter(base::OnceClosure start) {
  auto context = std::make_unique<base::OnceClosure>(std::move(start));
  pthread_attr_t attributes;
  pthread_attr_init(&attributes);
  pthread_attr_set_qos_class_np(&attributes, QOS_CLASS_USER_INITIATED, 0);
  g_started = pthread_create(&g_thread, &attributes, &Run, context.get()) == 0;
  pthread_attr_destroy(&attributes);
  if (g_started) {
    context.release();
  } else {
    std::move(*context).Run();
  }
}

void WaitForCrashReporter() {
  if (g_started) {
    pthread_join(g_thread, nullptr);
    g_started = false;
  }
}

}  // namespace fiber
