#ifndef FIBER_BROWSER_PALETTE_TAB_INDEX_SOURCE_H_
#define FIBER_BROWSER_PALETTE_TAB_INDEX_SOURCE_H_

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"

@protocol FiberTabIndex;
class Profile;

namespace content {
class WebContents;
}

namespace fiber {

class FiberBrowserWindow;
class PageText;

// Fills a profile's FiberTabIndex, which the command palettes of its windows
// search: the tabs of all its Fiber windows, and their pages' text. Made with
// the profile's first window, and deleted with its last.
class TabIndexSource {
 public:
  TabIndexSource(const TabIndexSource&) = delete;
  TabIndexSource& operator=(const TabIndexSource&) = delete;
  ~TabIndexSource();

  // The source for `window`'s profile, which now includes `window`.
  static TabIndexSource* AddWindow(FiberBrowserWindow* window);
  static void RemoveWindow(FiberBrowserWindow* window);

  id<FiberTabIndex> index() const { return index_; }

  // A window's tabs changed: the index gets all of them, soon.
  void TabsChanged();
  // Reads the text of the tab's page now, for the command palette opening.
  void ReadPageText(content::WebContents* web_contents);
  // Finds `text` in the tab's page, leaving it selected.
  void RevealText(content::WebContents* web_contents,
                  const std::u16string& text);

 private:
  explicit TabIndexSource(Profile* profile);

  static std::vector<std::unique_ptr<TabIndexSource>>& All();

  void SendTabs();
  PageText* PageTextFor(content::WebContents* web_contents);

  const raw_ptr<Profile> profile_;
  std::vector<raw_ptr<FiberBrowserWindow>> windows_;
  id<FiberTabIndex> __strong index_;
  // By tab ID.
  std::map<int32_t, std::unique_ptr<PageText>> page_texts_;
  bool is_send_pending_ = false;
  base::WeakPtrFactory<TabIndexSource> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_PALETTE_TAB_INDEX_SOURCE_H_
