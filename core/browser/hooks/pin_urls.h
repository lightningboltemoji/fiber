#ifndef FIBER_BROWSER_HOOKS_PIN_URLS_H_
#define FIBER_BROWSER_HOOKS_PIN_URLS_H_

#include "chrome/browser/ui/startup/startup_tab.h"
#include "ui/base/window_open_disposition.h"

class BrowserWindowInterface;
class GURL;

namespace fiber {

// A pin's page the user opens goes to the pin, rather than another tab.

// The user opening `url` from the omnibox (chrome::OpenCurrentURL()) in the
// active tab or a new one in front: goes to the pin whose page it is, if any,
// and returns whether there was one. From the pin's own tab, Chrome navigates
// as usual.
bool OpenURLInPin(BrowserWindowInterface* browser,
                  const GURL& url,
                  WindowOpenDisposition disposition);

// How Chrome opens `url` from the omnibox, given the `disposition` it chose:
// in a new tab in front rather than in a pin's tab, which stays on its page,
// unless `url` is the pin's page, the one the tab is on, or a javascript: URL.
WindowOpenDisposition DispositionForOmniboxURL(
    BrowserWindowInterface* browser,
    const GURL& url,
    WindowOpenDisposition disposition);

// Pages from other apps (AppController): goes to the pins of those that are
// pins' pages, and returns the rest, for Chrome to open.
StartupTabs OpenStartupTabsInPins(BrowserWindowInterface* browser,
                                  const StartupTabs& tabs);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_PIN_URLS_H_
