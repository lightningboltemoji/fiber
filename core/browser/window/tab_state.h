#ifndef FIBER_BROWSER_WINDOW_TAB_STATE_H_
#define FIBER_BROWSER_WINDOW_TAB_STATE_H_

#include <string>

@class FiberTabState;
class GURL;

namespace tabs {
class TabInterface;
}

namespace url {
struct Parsed;
}

namespace fiber {

// What the UI shows of `tab`: in its window's tab list, and in the command
// palette.
FiberTabState* TabStateFor(tabs::TabInterface* tab);

// `url` as the UI shows a tab's: a Unicode host, and no "https://". `parsed`,
// if given, gets its parts.
std::u16string DisplayURL(const GURL& url, url::Parsed* parsed = nullptr);

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_TAB_STATE_H_
