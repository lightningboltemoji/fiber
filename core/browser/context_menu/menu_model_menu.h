#ifndef FIBER_BROWSER_CONTEXT_MENU_MENU_MODEL_MENU_H_
#define FIBER_BROWSER_CONTEXT_MENU_MENU_MODEL_MENU_H_

@class NSEvent;
@class NSView;

namespace ui {
class MenuModel;
}

namespace fiber {

// Shows Chrome's menu `model` (an extension's, say) as a native menu
// (FiberContextMenuFactory) at `event`'s location in `view`, and returns once
// it's closed and the item chosen, if any, has run. Anything can happen
// meanwhile, `model` going away included.
void RunMenuModel(ui::MenuModel* model, NSEvent* event, NSView* view);

}  // namespace fiber

#endif  // FIBER_BROWSER_CONTEXT_MENU_MENU_MODEL_MENU_H_
