#ifndef FIBER_BROWSER_WINDOW_PAGE_THUMBNAIL_H_
#define FIBER_BROWSER_WINDOW_PAGE_THUMBNAIL_H_

#include <CoreGraphics/CoreGraphics.h>

@class NSImage;

namespace content {
class WebContents;
}

namespace tabs {
class TabInterface;
}

namespace fiber {

// Calls `completion` with a small image of what `web_contents`' page shows
// now, or with null if it hasn't drawn. The window dims itself by how light
// the page is.
void CapturePageThumbnail(content::WebContents* web_contents,
                          void (^completion)(CGImageRef thumbnail));

// What `tab` showed when it was last switched away from, as Chrome keeps it
// for its tab previews (ThumbnailTabHelper), or nil: if it hasn't been, or if
// the user turned tab preview images off in settings.
NSImage* TabPreview(tabs::TabInterface* tab);

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_PAGE_THUMBNAIL_H_
