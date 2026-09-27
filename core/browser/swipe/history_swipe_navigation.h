#ifndef FIBER_BROWSER_SWIPE_HISTORY_SWIPE_NAVIGATION_H_
#define FIBER_BROWSER_SWIPE_HISTORY_SWIPE_NAVIGATION_H_

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "content/public/browser/web_contents_observer.h"

namespace fiber {

// After a history swipe lands, waits for the page it went to to show, while
// the swipe's snapshot covers the tab: until the navigation commits and the
// page has sent a frame with it, or doesn't commit, or it's taken too long.
class HistorySwipeNavigation : public content::WebContentsObserver {
 public:
  // Runs `done` (later, never inside this call) once the page is showing.
  HistorySwipeNavigation(content::WebContents* web_contents,
                         base::OnceClosure done);
  HistorySwipeNavigation(const HistorySwipeNavigation&) = delete;
  HistorySwipeNavigation& operator=(const HistorySwipeNavigation&) = delete;
  ~HistorySwipeNavigation() override;

  // content::WebContentsObserver:
  void DidFinishNavigation(
      content::NavigationHandle* navigation_handle) override;
  void WebContentsDestroyed() override;

 private:
  // Finishes soon: a frame sent isn't quite a frame drawn.
  void FinishSoon();
  // Runs `done_`, which may delete this.
  void Finish();

  base::OnceClosure done_;
  // Runs Finish(): at the timeout, then sooner once the page is showing.
  base::OneShotTimer timer_;
  bool finishing_ = false;
  base::WeakPtrFactory<HistorySwipeNavigation> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_SWIPE_HISTORY_SWIPE_NAVIGATION_H_
