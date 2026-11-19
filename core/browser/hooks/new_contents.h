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

// Navigate() is opening a link as a peek (⌥-click, which Blink makes
// kNewPeek): makes `disposition` the tab in front that a peek is, and says
// whether it was one.
bool TakePeekDisposition(WindowOpenDisposition& disposition);

// Navigate() is about to insert `new_contents`, which `source` opened as a
// peek: marks it one, under the same conditions as WillAddNewContents() but
// the gesture, which Blink required already.
void WillAddPeekContents(BrowserWindowInterface* browser,
                         content::WebContents* source,
                         content::WebContents* new_contents);

// Navigate() put `new_contents` in `browser` for a link opened in a split
// (⌘⌥-click), in place of Chrome's pairing it with the active tab: the
// window's split pairs them (see split/tab_split.h), and it becomes active.
void DidAddSplitContents(BrowserWindowInterface* browser,
                         content::WebContents* source,
                         content::WebContents* new_contents);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_NEW_CONTENTS_H_
