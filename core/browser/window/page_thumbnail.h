#ifndef FIBER_BROWSER_WINDOW_PAGE_THUMBNAIL_H_
#define FIBER_BROWSER_WINDOW_PAGE_THUMBNAIL_H_

#include <CoreGraphics/CoreGraphics.h>

namespace content {
class WebContents;
}

namespace fiber {

// Calls `completion` with a small image of what `web_contents`' page shows
// now, or with null if it hasn't drawn. The window dims itself by how light
// the page is.
void CapturePageThumbnail(content::WebContents* web_contents,
                          void (^completion)(CGImageRef thumbnail));

}  // namespace fiber

#endif  // FIBER_BROWSER_WINDOW_PAGE_THUMBNAIL_H_
