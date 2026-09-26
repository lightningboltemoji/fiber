#include "fiber/browser/hooks/browser_window_factory.h"

#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "fiber/browser/window/fiber_browser_window.h"

namespace fiber {

std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateBrowserWindow(
    BrowserWindowInterface* browser) {
  switch (browser->GetType()) {
    case BrowserWindowInterface::Type::TYPE_NORMAL:
    case BrowserWindowInterface::Type::TYPE_POPUP:
      return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(
          new FiberBrowserWindow(browser));
    default:
      // DevTools, app, and picture-in-picture windows keep Chrome's UI for now.
      return nullptr;
  }
}

}  // namespace fiber
