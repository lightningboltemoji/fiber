#ifndef FIBER_BROWSER_NEW_TAB_NEW_TAB_PAGE_UI_H_
#define FIBER_BROWSER_NEW_TAB_NEW_TAB_PAGE_UI_H_

#include "content/public/browser/web_ui_controller.h"
#include "content/public/browser/webui_config.h"

namespace fiber {

class NewTabPageUI;

// chrome://newtab, which Chrome would rewrite to its own New Tab page.
class NewTabPageUIConfig : public content::DefaultWebUIConfig<NewTabPageUI> {
 public:
  NewTabPageUIConfig();
};

// Fiber's New Tab page. The window draws it natively; the page itself is
// empty, in the window's background color, so it looks the same while Chrome
// holds its last frame during a navigation away.
class NewTabPageUI : public content::WebUIController {
 public:
  explicit NewTabPageUI(content::WebUI* web_ui);
  NewTabPageUI(const NewTabPageUI&) = delete;
  NewTabPageUI& operator=(const NewTabPageUI&) = delete;
  ~NewTabPageUI() override;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_NEW_TAB_NEW_TAB_PAGE_UI_H_
