#include "fiber/browser/favicons/favicon_image.h"

#import <AppKit/AppKit.h>

#include "fiber/browser/hooks/web_ui_favicons.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

namespace fiber {

NSImage* FaviconImage(const gfx::Image& favicon, const GURL& page_url) {
  // The shared one when it needn't change, so the UI can tell it's the same.
  NSImage* image = favicon.AsNSImage();
  bool is_template = HasFiberFavicon(page_url);
  if (image.isTemplate == is_template) {
    return image;
  }
  // A copy, since the gfx::Image shares its NSImage with everything showing it.
  image = [image copy];
  [image setTemplate:is_template];
  return image;
}

}  // namespace fiber
