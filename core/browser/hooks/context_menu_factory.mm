#include "fiber/browser/hooks/context_menu_factory.h"

#include "chrome/browser/devtools/devtools_window.h"
#include "fiber/browser/context_menu/fiber_render_view_context_menu.h"
#include "fiber/browser/window/fiber_browser_window.h"

namespace fiber {

std::unique_ptr<RenderViewContextMenuMac> CreateContextMenu(
    content::WebContents* web_contents,
    content::RenderFrameHost& render_frame_host,
    const content::ContextMenuParams& params,
    bool is_paste_enabled,
    bool is_paste_and_match_style_enabled) {
  // DevTools' menus are mostly its own items, which Fiber's leaves out.
  if (!FiberBrowserWindow::FromWebContents(web_contents) ||
      DevToolsWindow::IsDevToolsWindow(web_contents)) {
    return nullptr;
  }
  return std::make_unique<FiberRenderViewContextMenu>(
      render_frame_host, params, is_paste_enabled,
      is_paste_and_match_style_enabled);
}

}  // namespace fiber
