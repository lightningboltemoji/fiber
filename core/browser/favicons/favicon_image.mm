#include "fiber/browser/favicons/favicon_image.h"

#import <AppKit/AppKit.h>

#include "fiber/browser/hooks/web_ui_favicons.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

namespace fiber {

NSImage* FaviconImage(const gfx::Image& favicon, const GURL& page_url) {
  // A copy, since the gfx::Image shares its NSImage with everything showing it.
  NSImage* image = [favicon.AsNSImage() copy];
  [image setTemplate:HasFiberFavicon(page_url)];
  return image;
}

}  // namespace fiber
