#include "fiber/browser/window/page_thumbnail.h"

#include <algorithm>

#include "base/apple/scoped_cftyperef.h"
#include "base/functional/bind.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/utils/mac/SkCGUtils.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

namespace fiber {

namespace {

// The thumbnail's longer side, in pixels. The GPU scales it down, so it's
// only this much to read back.
constexpr int kThumbnailSize = 32;

}  // namespace

void CapturePageThumbnail(content::WebContents* web_contents,
                          void (^completion)(CGImageRef thumbnail)) {
  content::RenderWidgetHostView* view =
      web_contents ? web_contents->GetRenderWidgetHostView() : nullptr;
  const gfx::Size size = view ? view->GetViewBounds().size() : gfx::Size();
  if (!view || !view->IsSurfaceAvailableForCopy() || size.IsEmpty()) {
    completion(nullptr);
    return;
  }
  const float scale = static_cast<float>(kThumbnailSize) /
                      std::max(size.width(), size.height());
  view->CopyFromSurface(
      /*src_rect=*/gfx::Rect(), gfx::ScaleToCeiledSize(size, scale),
      base::TimeDelta(),
      base::BindPostTask(
          base::SequencedTaskRunner::GetCurrentDefault(),
          base::BindOnce(^(const content::CopyFromSurfaceResult& result) {
            if (!result.has_value() || result->bitmap.drawsNothing()) {
              completion(nullptr);
              return;
            }
            base::apple::ScopedCFTypeRef<CGImageRef> image(
                SkCreateCGImageRef(result->bitmap));
            completion(image.get());
          })));
}

}  // namespace fiber
