#include "fiber/browser/hooks/browser_window_factory.h"

#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "fiber/browser/extensions/fiber_extension_window.h"
#include "fiber/browser/window/fiber_browser_window.h"

namespace fiber {

std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateBrowserWindow(
    BrowserWindowInterface* browser) {
  switch (browser->GetType()) {
    case BrowserWindowInterface::Type::TYPE_NORMAL:
    case BrowserWindowInterface::Type::TYPE_POPUP:
      return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(
          new FiberBrowserWindow(browser));
    case BrowserWindowInterface::Type::TYPE_APP_POPUP:
      if (!FiberExtensionWindow::IsExtensionWindow(browser)) {
        return nullptr;
      }
      // A bubble over the browser window, or one of its own if there's none.
      if (FiberBrowserWindow* host = FiberExtensionWindow::HostFor(browser)) {
        return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(
            new FiberExtensionWindow(browser, host));
      }
      return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(
          new FiberBrowserWindow(browser));
    default:
      // DevTools, web app and picture-in-picture windows keep Chrome's UI.
      return nullptr;
  }
}

bool IsInFiberWindow(content::WebContents* web_contents) {
  return web_contents &&
         FiberBrowserWindow::FromWebContents(web_contents) != nullptr;
}

}  // namespace fiber
