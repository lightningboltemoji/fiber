#ifndef FIBER_BROWSER_FAVICONS_FAVICON_IMAGE_H_
#define FIBER_BROWSER_FAVICONS_FAVICON_IMAGE_H_

@class NSImage;
class GURL;

namespace gfx {
class Image;
}

namespace fiber {

// The favicon of the page at `page_url`, for Fiber's UI: a template, to draw in
// the color of its text, when it's one Fiber picked (see HasFiberFavicon()).
NSImage* FaviconImage(const gfx::Image& favicon, const GURL& page_url);

}  // namespace fiber

#endif  // FIBER_BROWSER_FAVICONS_FAVICON_IMAGE_H_
