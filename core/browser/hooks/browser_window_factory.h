#ifndef FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_
#define FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_

#include <memory>

#include "chrome/browser/ui/browser_window_deleter.h"
#include "ui/gfx/native_ui_types.h"

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
// Whether `window`, which may be null, is a Fiber window.
bool IsFiberWindow(gfx::NativeWindow window);
// Whether `browser`'s window is Fiber's: a browser window, or an extension's
// window as a bubble over one.
bool IsFiberBrowser(BrowserWindowInterface* browser);
// Whether `browser`'s window is an extension's, as a bubble over a Fiber
// window.
bool IsExtensionWindowBubble(BrowserWindowInterface* browser);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_BROWSER_WINDOW_FACTORY_H_
