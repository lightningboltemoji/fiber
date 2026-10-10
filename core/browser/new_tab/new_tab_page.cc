#include "fiber/browser/new_tab/new_tab_page.h"

#include "chrome/common/webui_url_constants.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/url_constants.h"
#include "url/gurl.h"

namespace fiber {

bool ShowsNewTabPage(content::WebContents* contents) {
  content::NavigationEntry* entry = contents->GetController().GetVisibleEntry();
  const GURL url = entry ? entry->GetVirtualURL() : GURL();
  return url.SchemeIs(content::kChromeUIScheme) &&
         url.host() == chrome::kChromeUINewTabHost;
}

bool IsBlankNewTabPage(content::WebContents* contents) {
  return ShowsNewTabPage(contents) &&
         contents->GetController().GetEntryCount() <= 1;
}

}  // namespace fiber
