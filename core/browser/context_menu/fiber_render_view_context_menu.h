#ifndef FIBER_BROWSER_CONTEXT_MENU_FIBER_RENDER_VIEW_CONTEXT_MENU_H_
#define FIBER_BROWSER_CONTEXT_MENU_FIBER_RENDER_VIEW_CONTEXT_MENU_H_

#import <Foundation/Foundation.h>

#include <string>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/cocoa/renderer_context_menu/render_view_context_menu_mac.h"

@class FiberContextMenuItem;
@class FiberRenderViewContextMenuActions;
@protocol FiberContextMenu;

namespace ui {
class MenuModel;
}

namespace fiber {

// A page's context menu in a Fiber window: Chrome's menu (what's in it, and
// what each item does, extensions' items included), with the items Fiber
// shows, shown by Fiber's UI (FiberContextMenuFactory).
class FiberRenderViewContextMenu : public RenderViewContextMenuMac {
 public:
  FiberRenderViewContextMenu(content::RenderFrameHost& render_frame_host,
                             const content::ContextMenuParams& params,
                             bool is_paste_enabled,
                             bool is_paste_and_match_style_enabled);
  FiberRenderViewContextMenu(const FiberRenderViewContextMenu&) = delete;
  FiberRenderViewContextMenu& operator=(const FiberRenderViewContextMenu&) =
      delete;
  ~FiberRenderViewContextMenu() override;

  // Called by the menu's actions.
  void OnMenuWillOpen();
  void OnMenuDidClose();
  // May delete this.
  void OnItemSelected(NSInteger item_id);

  // RenderViewContextMenuBase:
  void Show() override;

 protected:
  // RenderViewContextMenuMac:
  void CancelToolkitMenu() override;
  void UpdateToolkitMenuItem(int command_id,
                             bool enabled,
                             bool hidden,
                             const std::u16string& title) override;

 private:
  // An item in the UI's menu: the item at `index` in `model`, which is this
  // menu's model or one of its submenus'.
  struct Item {
    base::WeakPtr<ui::MenuModel> model;
    size_t index;
  };

  // The UI's items for `model`'s, and records them in `items_`.
  NSArray<FiberContextMenuItem*>* ItemsFromModel(ui::MenuModel* model);

  // Indexed by the UI's item IDs.
  std::vector<Item> items_;
  FiberRenderViewContextMenuActions* __strong actions_;
  id<FiberContextMenu> __strong menu_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_CONTEXT_MENU_FIBER_RENDER_VIEW_CONTEXT_MENU_H_
