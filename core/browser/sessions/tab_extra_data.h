#ifndef FIBER_BROWSER_SESSIONS_TAB_EXTRA_DATA_H_
#define FIBER_BROWSER_SESSIONS_TAB_EXTRA_DATA_H_

#include <string>

namespace content {
class WebContents;
}

namespace fiber {

// Keeps `value` under `key` in the session of `contents`, once it's a tab in
// a window; empty clears it. It comes back with the tab (see
// hooks/tab_extra_data.h).
void SaveTabExtraData(content::WebContents* contents,
                      const char* key,
                      const std::string& value);

}  // namespace fiber

#endif  // FIBER_BROWSER_SESSIONS_TAB_EXTRA_DATA_H_
