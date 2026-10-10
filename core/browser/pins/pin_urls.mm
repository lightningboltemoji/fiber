#include "fiber/browser/hooks/pin_urls.h"

#include <string>

#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/tabs/public/tab_interface.h"
#include "fiber/browser/new_tab/new_tab_page.h"
#include "fiber/browser/pins/pin_store.h"
#include "fiber/browser/pins/pinned_tabs.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "url/gurl.h"

namespace fiber {

namespace {

PinnedTabs* PinnedTabsFor(BrowserWindowInterface* browser) {
  FiberBrowserWindow* window = FiberBrowserWindow::FromBrowser(browser);
  return window ? window->pinned_tabs() : nullptr;
}

}  // namespace

bool OpenURLInPin(BrowserWindowInterface* browser,
                  const GURL& url,
                  WindowOpenDisposition disposition) {
  PinnedTabs* pinned_tabs = PinnedTabsFor(browser);
  if (!pinned_tabs || (disposition != WindowOpenDisposition::CURRENT_TAB &&
                       disposition != WindowOpenDisposition::NEW_FOREGROUND_TAB)) {
    return false;
  }
  const Pin* pin = pinned_tabs->PinForURL(url);
  TabStripModel* model = browser->GetTabStripModel();
  tabs::TabInterface* from = model->GetActiveTab();
  if (!pin || (from && pinned_tabs->PinForTab(from) == pin)) {
    return false;
  }
  pinned_tabs->Show(std::string(pin->id));
  // As Chrome's switching to a tab from the omnibox does, the blank New Tab
  // page it was typed on goes, unless the window has no other tab that isn't
  // a pin's.
  const int index = from ? model->GetIndexOfTab(from) : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab && index != model->active_index() &&
      !from->IsPinned() && IsBlankNewTabPage(from->GetContents()) &&
      model->count() - model->IndexOfFirstNonPinnedTab() > 1) {
    model->CloseWebContentsAt(index, TabCloseTypes::CLOSE_NONE);
  }
  return true;
}

StartupTabs OpenStartupTabsInPins(BrowserWindowInterface* browser,
                                  const StartupTabs& tabs) {
  PinnedTabs* pinned_tabs = PinnedTabsFor(browser);
  if (!pinned_tabs) {
    return tabs;
  }
  StartupTabs rest;
  for (const StartupTab& tab : tabs) {
    if (const Pin* pin = pinned_tabs->PinForURL(tab.url)) {
      pinned_tabs->Show(std::string(pin->id));
    } else {
      rest.push_back(tab);
    }
  }
  return rest;
}

}  // namespace fiber
