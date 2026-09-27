#ifndef FIBER_BROWSER_SWIPE_PAGE_SNAPSHOTS_H_
#define FIBER_BROWSER_SWIPE_PAGE_SNAPSHOTS_H_

@class NSImage;

namespace content {
class WebContents;
}

// Snapshots of the pages the user leaves, so a history swipe shows the page
// it's going to before that page draws: what it looked like as it was left,
// at the display's resolution, keyed by its navigation entry. Only the most
// recently taken are kept, within a memory budget.
namespace fiber {

// Snapshots `web_contents`' page as it is now, for its current entry. Called
// as a navigation away from it starts.
void CapturePageSnapshot(content::WebContents* web_contents);

// The snapshot of `web_contents`' entry `offset` entries back (negative) or
// forward from the current one, if there's one.
NSImage* PageSnapshotAtOffset(content::WebContents* web_contents, int offset);

}  // namespace fiber

#endif  // FIBER_BROWSER_SWIPE_PAGE_SNAPSHOTS_H_
