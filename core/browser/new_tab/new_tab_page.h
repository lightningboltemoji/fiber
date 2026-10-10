#ifndef FIBER_BROWSER_NEW_TAB_NEW_TAB_PAGE_H_
#define FIBER_BROWSER_NEW_TAB_NEW_TAB_PAGE_H_

namespace content {
class WebContents;
}

namespace fiber {

// Whether `contents` shows a New Tab page, Fiber's or an extension's.
bool ShowsNewTabPage(content::WebContents* contents);

// Whether it shows a New Tab page and never showed anything else, which
// Command-T goes back to rather than opening another.
bool IsBlankNewTabPage(content::WebContents* contents);

}  // namespace fiber

#endif  // FIBER_BROWSER_NEW_TAB_NEW_TAB_PAGE_H_
