#ifndef FIBER_BROWSER_HOOKS_WEB_UI_FAVICONS_H_
#define FIBER_BROWSER_HOOKS_WEB_UI_FAVICONS_H_

#include "base/memory/scoped_refptr.h"
#include "content/public/common/url_constants.h"
#include "ui/base/resource/resource_scale_factor.h"
#include "url/gurl.h"

namespace base {
class RefCountedMemory;
}

namespace fiber {

// Whether the page at `page_url` has Fiber's favicon rather than the icons it
// links: every chrome:// page does. Inline for FaviconDriverImpl, which links
// apart from //fiber (see patches/chromium/
// components-favicon-core-favicon_driver_impl.cc.patch).
inline bool HasFiberFavicon(const GURL& page_url) {
  return page_url.SchemeIs(content::kChromeUIScheme);
}

// The favicon of the chrome:// page at `page_url`, as a PNG. Called from
// ChromeWebUIControllerFactory::GetFaviconForURL() (see patches/chromium/
// chrome-browser-ui-webui-chrome_web_ui_controller_factory.cc.patch).
scoped_refptr<base::RefCountedMemory> GetWebUIFavicon(
    const GURL& page_url,
    ui::ResourceScaleFactor scale_factor);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_WEB_UI_FAVICONS_H_
