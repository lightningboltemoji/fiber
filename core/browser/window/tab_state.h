#ifndef FIBER_BROWSER_WINDOW_TAB_STATE_H_
#define FIBER_BROWSER_WINDOW_TAB_STATE_H_

@class FiberTabState;

namespace tabs {
class TabInterface;
}

namespace fiber {

// What the UI shows of `tab`: in its window's tab list, and in the command
// palette.
FiberTabState* TabStateFor(tabs::TabInterface* tab);

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_TAB_STATE_H_
