#ifndef FIBER_BROWSER_PALETTE_PAGE_TEXT_H_
#define FIBER_BROWSER_PALETTE_PAGE_TEXT_H_

#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_tab_helper.h"
#include "content/public/browser/web_contents_observer.h"

namespace content_extraction {
struct InnerTextResult;
}

namespace fiber {

// The command palette's view of a tab's page. It reads the page's text: once
// the page has loaded and settled, after it changes its URL itself, when the
// user leaves the tab (pages change without loading), and when asked. And it
// selects text the palette found there.
class PageText : public content::WebContentsObserver,
                 public find_in_page::FindResultObserver {
 public:
  // `on_text` gets the page's text, or empty text once the tab has left the
  // page it was read from.
  PageText(content::WebContents* web_contents,
           base::RepeatingCallback<void(const std::string&)> on_text);
  PageText(const PageText&) = delete;
  PageText& operator=(const PageText&) = delete;
  ~PageText() override;

  void Read();
  // Finds `text` in the page, once it's loaded, leaving it selected.
  void Reveal(const std::u16string& text);

  // content::WebContentsObserver:
  void DidStopLoading() override;
  void PrimaryPageChanged(content::Page& page) override;
  void DidFinishNavigation(
      content::NavigationHandle* navigation_handle) override;
  void OnVisibilityChanged(content::Visibility visibility) override;

  // find_in_page::FindResultObserver:
  void OnFindResultAvailable(content::WebContents* web_contents) override;

 private:
  void ReadSoon(base::TimeDelta delay);
  void OnInnerText(int page,
                   std::unique_ptr<content_extraction::InnerTextResult> result);
  void FindRevealText();

  base::RepeatingCallback<void(const std::string&)> on_text_;
  base::OneShotTimer read_timer_;
  // Counts the pages the tab has shown, so text from one it's left is dropped.
  int page_ = 0;
  base::TimeTicks last_read_;
  // To find once the page has loaded.
  std::u16string reveal_text_;
  base::ScopedObservation<find_in_page::FindTabHelper,
                          find_in_page::FindResultObserver>
      find_observation_{this};
  base::WeakPtrFactory<PageText> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_PALETTE_PAGE_TEXT_H_
