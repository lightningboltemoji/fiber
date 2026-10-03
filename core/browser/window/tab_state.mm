#include "fiber/browser/window/tab_state.h"

#import "FiberBridge/FiberTabState.h"
#include "base/strings/escape.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/tabs/public/tab_interface.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/favicons/favicon_image.h"
#include "ui/gfx/image/image.h"
#include "url/third_party/mozilla/url_parse.h"

namespace fiber {

FiberTabState* TabStateFor(tabs::TabInterface* tab) {
  content::WebContents* contents = tab->GetContents();
  favicon::ContentFaviconDriver* favicon_driver =
      favicon::ContentFaviconDriver::FromWebContents(contents);
  NSImage* favicon = favicon_driver && favicon_driver->FaviconIsValid()
                         ? FaviconImage(favicon_driver->GetFavicon(),
                                        contents->GetLastCommittedURL())
                         : nil;
  url::Parsed parsed;
  std::u16string url = url_formatter::FormatUrl(
      contents->GetVisibleURL(),
      url_formatter::kFormatUrlOmitDefaults |
          url_formatter::kFormatUrlOmitHTTPS |
          url_formatter::kFormatUrlOmitTrivialSubdomains,
      base::UnescapeRule::SPACES, &parsed, nullptr, nullptr);
  size_t origin_end = 0;
  if (parsed.host.is_nonempty()) {
    origin_end = static_cast<size_t>(
        (parsed.port.is_valid() ? parsed.port : parsed.host).end());
  }
  return [[FiberTabState alloc]
          initWithID:tab->GetHandle().raw_value()
               title:base::SysUTF16ToNSString(contents->GetTitle())
                 url:base::SysUTF16ToNSString(url)
              origin:base::SysUTF16ToNSString(url.substr(0, origin_end))
             favicon:favicon
             loading:contents->ShouldShowLoadingUI()
      lastActiveTime:contents->GetLastActiveTime().ToNSDate()];
}

}  // namespace fiber
