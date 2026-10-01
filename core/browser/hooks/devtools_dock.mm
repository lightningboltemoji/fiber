#include "fiber/browser/hooks/devtools_dock.h"

#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "fiber/browser/window/fiber_browser_window.h"

namespace fiber {

bool CanDockDevTools(BrowserWindowInterface* browser) {
  // Like DevtoolsUIController: browser windows, not popups.
  return FiberBrowserWindow::FromBrowser(browser) &&
         browser->GetType() == BrowserWindowInterface::Type::TYPE_NORMAL;
}

void UpdateDevTools(BrowserWindowInterface* browser,
                    content::WebContents* inspected_web_contents) {
  FiberBrowserWindow* window = FiberBrowserWindow::FromBrowser(browser);
  if (window && window->browser()->GetTabStripModel()->GetActiveWebContents() ==
                    inspected_web_contents) {
    window->UpdateDevTools();
  }
}

}  // namespace fiber
