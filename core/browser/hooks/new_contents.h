#ifndef FIBER_BROWSER_HOOKS_NEW_CONTENTS_H_
#define FIBER_BROWSER_HOOKS_NEW_CONTENTS_H_

#include "ui/base/window_open_disposition.h"

class BrowserWindowInterface;

namespace content {
class WebContents;
}

namespace fiber {

// A page, `source`, opened `new_contents` (`target=_blank`, `window.open()`),
// which Chrome is about to insert: marks it a peek over `source` (see
// peek/tab_peek.h) if it's a tab in front that the user's gesture opened from
// the active tab of a window without a split. Called by
// BrowserWebContentsDelegate::AddNewContents(), which the omnibox, extensions
// and modified clicks on ordinary links don't go through.
void WillAddNewContents(BrowserWindowInterface* browser,
                        content::WebContents* source,
                        content::WebContents* new_contents,
                        WindowOpenDisposition disposition,
                        bool user_gesture);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_NEW_CONTENTS_H_
