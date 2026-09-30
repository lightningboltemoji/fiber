#ifndef FIBER_BROWSER_HOOKS_SAD_TAB_H_
#define FIBER_BROWSER_HOOKS_SAD_TAB_H_

#include <memory>

#include "chrome/browser/ui/sad_tab_types.h"

class SadTab;

namespace content {
class WebContents;
}

namespace fiber {

// For SadTab::Create() in a Fiber window: Fiber's sad tab, which the window
// draws over the page (SadTabView.swift), in place of Chrome's views one.
std::unique_ptr<SadTab> CreateSadTab(content::WebContents* web_contents,
                                     SadTabKind kind);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_SAD_TAB_H_
