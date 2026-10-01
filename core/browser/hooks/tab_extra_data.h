#ifndef FIBER_BROWSER_HOOKS_TAB_EXTRA_DATA_H_
#define FIBER_BROWSER_HOOKS_TAB_EXTRA_DATA_H_

#include <map>
#include <string>

namespace content {
class WebContents;
}

namespace fiber {

// What Fiber keeps of a tab in its session and closed-tab history: which pin
// it's the page of (pins/pinned_tab_data.h). Called by BuildCommandsForTab(),
// which otherwise drops it, and BrowserLiveTabContext::GetExtraDataForTab().
std::map<std::string, std::string> TabExtraData(content::WebContents* contents);

// Called by CreateRestoredTab() (browser_tabrestore.cc), before the tab is in
// a window.
void RestoreTabExtraData(content::WebContents* contents,
                         const std::map<std::string, std::string>& extra_data);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_TAB_EXTRA_DATA_H_
