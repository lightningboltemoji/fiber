#include "fiber/browser/swipe/page_snapshots.h"

#import <AppKit/AppKit.h>

#include "base/containers/lru_cache.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_view_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/skia/include/core/SkBitmap.h"

namespace fiber {

namespace {

// What the snapshots may take, all tabs together: about 20 full-window
// snapshots of a large Retina window.
constexpr size_t kBudgetBytes = 160 * 1024 * 1024;

struct Snapshot {
  NSImage* __strong image;
  size_t bytes = 0;
};

// Snapshots by navigation entry (their IDs are unique across tabs), the most
// recently taken first.
class SnapshotStore {
 public:
  SnapshotStore() : snapshots_(base::LRUCache<int, Snapshot>::NO_AUTO_EVICT) {}

  void Put(int entry_id, Snapshot snapshot) {
    if (auto it = snapshots_.Peek(entry_id); it != snapshots_.end()) {
      bytes_ -= it->second.bytes;
      snapshots_.Erase(it);
    }
    bytes_ += snapshot.bytes;
    snapshots_.Put(entry_id, std::move(snapshot));
    while (bytes_ > kBudgetBytes && snapshots_.size() > 1) {
      auto oldest = snapshots_.rbegin();
      bytes_ -= oldest->second.bytes;
      snapshots_.Erase(oldest);
    }
  }

  NSImage* Get(int entry_id) {
    auto it = snapshots_.Peek(entry_id);
    return it == snapshots_.end() ? nil : it->second.image;
  }

 private:
  base::LRUCache<int, Snapshot> snapshots_;
  size_t bytes_ = 0;
};

SnapshotStore& Store() {
  static base::NoDestructor<SnapshotStore> store;
  return *store;
}

}  // namespace

void CapturePageSnapshot(content::WebContents* web_contents) {
  content::NavigationEntry* entry =
      web_contents->GetController().GetLastCommittedEntry();
  content::RenderWidgetHostView* view = web_contents->GetRenderWidgetHostView();
  if (!entry || !view || !view->IsSurfaceAvailableForCopy()) {
    return;
  }
  int entry_id = entry->GetUniqueID();
  // The whole page, at the display's resolution.
  view->CopyFromSurface(
      /*src_rect=*/gfx::Rect(), /*output_size=*/gfx::Size(), base::TimeDelta(),
      base::BindPostTask(
          base::SequencedTaskRunner::GetCurrentDefault(),
          base::BindOnce(
              [](int entry_id, const content::CopyFromSurfaceResult& result) {
                if (!result.has_value() || result->bitmap.drawsNothing()) {
                  return;
                }
                const SkBitmap& bitmap = result->bitmap;
                Store().Put(entry_id,
                            {.image = skia::SkBitmapToNSImage(bitmap),
                             .bytes = bitmap.computeByteSize()});
              },
              entry_id)));
}

NSImage* PageSnapshotAtOffset(content::WebContents* web_contents, int offset) {
  content::NavigationEntry* entry =
      web_contents->GetController().GetEntryAtOffset(offset);
  return entry ? Store().Get(entry->GetUniqueID()) : nil;
}

}  // namespace fiber
