#ifndef FIBER_BROWSER_HOOKS_CONTEXT_MENU_FACTORY_H_
#define FIBER_BROWSER_HOOKS_CONTEXT_MENU_FACTORY_H_

#include <memory>

#include "content/public/browser/context_menu_params.h"

class RenderViewContextMenuMac;

namespace content {
class RenderFrameHost;
class WebContents;
}  // namespace content

namespace fiber {

// Null unless `web_contents` is a tab in a Fiber window. Called from
// ChromeWebContentsViewDelegateViewsMac::BuildMenu() (see patches/chromium/
// chrome-browser-ui-views-tab_contents-chrome_web_contents_view_delegate_views_mac.mm.patch).
std::unique_ptr<RenderViewContextMenuMac> CreateContextMenu(
    content::WebContents* web_contents,
    content::RenderFrameHost& render_frame_host,
    const content::ContextMenuParams& params,
    bool is_paste_enabled,
    bool is_paste_and_match_style_enabled);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_CONTEXT_MENU_FACTORY_H_
