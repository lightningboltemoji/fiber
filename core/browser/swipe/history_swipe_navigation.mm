#include "fiber/browser/swipe/history_swipe_navigation.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/time/time.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"

namespace fiber {

namespace {

// The longest the snapshot covers the page: past this, the page shows as it
// is, loading or not.
constexpr base::TimeDelta kTimeout = base::Milliseconds(1500);

// From a frame sent to its drawing, about two display refreshes.
constexpr base::TimeDelta kFrameDelay = base::Milliseconds(32);

}  // namespace

HistorySwipeNavigation::HistorySwipeNavigation(
    content::WebContents* web_contents,
    base::OnceClosure done)
    : content::WebContentsObserver(web_contents), done_(std::move(done)) {
  timer_.Start(FROM_HERE, kTimeout,
               base::BindOnce(&HistorySwipeNavigation::Finish,
                              base::Unretained(this)));
}

HistorySwipeNavigation::~HistorySwipeNavigation() = default;

void HistorySwipeNavigation::DidFinishNavigation(
    content::NavigationHandle* navigation_handle) {
  if (!navigation_handle->IsInPrimaryMainFrame()) {
    return;
  }
  if (!navigation_handle->HasCommitted()) {
    // It isn't coming (the page asked to stay, say): the page is as it was.
    FinishSoon();
    return;
  }
  navigation_handle->GetRenderFrameHost()->InsertVisualStateCallback(
      base::BindOnce(
          [](base::WeakPtr<HistorySwipeNavigation> navigation, bool) {
            if (navigation) {
              navigation->FinishSoon();
            }
          },
          weak_factory_.GetWeakPtr()));
}

void HistorySwipeNavigation::WebContentsDestroyed() {
  FinishSoon();
}

void HistorySwipeNavigation::FinishSoon() {
  if (finishing_) {
    return;
  }
  finishing_ = true;
  // In place of the timeout.
  timer_.Start(FROM_HERE, kFrameDelay,
               base::BindOnce(&HistorySwipeNavigation::Finish,
                              base::Unretained(this)));
}

void HistorySwipeNavigation::Finish() {
  std::move(done_).Run();
}

}  // namespace fiber
