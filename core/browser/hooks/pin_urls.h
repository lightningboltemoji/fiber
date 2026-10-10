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

// Pages from other apps (AppController): goes to the pins of those that are
// pins' pages, and returns the rest, for Chrome to open.
StartupTabs OpenStartupTabsInPins(BrowserWindowInterface* browser,
                                  const StartupTabs& tabs);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_PIN_URLS_H_
