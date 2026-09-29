#include "fiber/browser/window/tab_state.h"

#import "FiberBridge/FiberTabState.h"
#include "base/strings/escape.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/tabs/public/tab_interface.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/image/image.h"

namespace fiber {

FiberTabState* TabStateFor(tabs::TabInterface* tab) {
  content::WebContents* contents = tab->GetContents();
  favicon::ContentFaviconDriver* favicon_driver =
      favicon::ContentFaviconDriver::FromWebContents(contents);
  NSImage* favicon = favicon_driver && favicon_driver->FaviconIsValid()
                         ? favicon_driver->GetFavicon().AsNSImage()
                         : nil;
  std::u16string url = url_formatter::FormatUrl(
      contents->GetVisibleURL(),
      url_formatter::kFormatUrlOmitDefaults |
          url_formatter::kFormatUrlOmitHTTPS |
          url_formatter::kFormatUrlOmitTrivialSubdomains,
      base::UnescapeRule::SPACES, nullptr, nullptr, nullptr);
  return [[FiberTabState alloc]
          initWithID:tab->GetHandle().raw_value()
               title:base::SysUTF16ToNSString(contents->GetTitle())
                 url:base::SysUTF16ToNSString(url)
             favicon:favicon
             loading:contents->ShouldShowLoadingUI()
      lastActiveTime:contents->GetLastActiveTime().ToNSDate()];
}

}  // namespace fiber
