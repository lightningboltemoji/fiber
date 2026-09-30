#ifndef FIBER_BROWSER_HOOKS_DIALOG_MODELS_H_
#define FIBER_BROWSER_HOOKS_DIALOG_MODELS_H_

#include <memory>

#include "ui/gfx/native_ui_types.h"

namespace content {
class WebContents;
}

namespace ui {
class DialogModel;
}

// Chrome's ui::DialogModel dialogs as Fiber prompts, over the veiled page, in
// place of views' BubbleDialogModelHost. One with what a prompt can't show (a
// combobox, a views field) ends at once, as if dismissed.
namespace fiber {

// For chrome::ShowTabModal() and extensions' ShowWebModalDialog(): until the
// tab closes or leaves the site.
void ShowTabModalDialog(std::unique_ptr<ui::DialogModel> dialog_model,
                        content::WebContents* web_contents);

// For chrome::ShowBrowserModal() and extensions' ShowModalDialog(), in Fiber
// window `window`: until the window closes.
void ShowWindowModalDialog(std::unique_ptr<ui::DialogModel> dialog_model,
                           gfx::NativeWindow window);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_DIALOG_MODELS_H_
