#ifndef FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_
#define FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_

#include <memory>

#include "chrome/browser/ui/browser_window_deleter.h"

class BrowserWindow;
class BrowserWindowInterface;

namespace fiber {

// Called from BrowserWindow::CreateBrowserWindow() (see
// patches/chromium/chrome-browser-ui-views-frame-browser_window_factory.cc.patch)
// so that Chrome's browsers are shown in Fiber's windows. Returns null for
// browser types Fiber doesn't handle yet, which get Chrome's own window.
std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateBrowserWindow(
    BrowserWindowInterface* browser);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_
