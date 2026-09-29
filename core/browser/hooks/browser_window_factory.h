#ifndef FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_
#define FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_

#include <memory>

#include "chrome/browser/ui/browser_window_deleter.h"

class BrowserWindow;
class BrowserWindowInterface;

namespace content {
class WebContents;
}

namespace fiber {

// Called from BrowserWindow::CreateBrowserWindow() (see
// patches/chromium/chrome-browser-ui-views-frame-browser_window_factory.cc.patch).
// Null for browser types Fiber doesn't handle, which get Chrome's own window.
std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateBrowserWindow(
    BrowserWindowInterface* browser);

// For Chrome's factories whose views UI needs a views window to attach to:
// whether the tab `web_contents`, which may be null, is in a Fiber window.
bool IsInFiberWindow(content::WebContents* web_contents);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_
