#include "fiber/browser/hooks/javascript_dialog_factory.h"

#include <utility>

#include "base/check.h"
#include "base/functional/callback.h"
#include "fiber/browser/dialogs/fiber_javascript_dialog_view.h"
#include "fiber/browser/window/fiber_browser_window.h"

namespace fiber {

bool IsInFiberWindow(content::WebContents* web_contents) {
  return FiberBrowserWindow::FromWebContents(web_contents) != nullptr;
}

base::WeakPtr<javascript_dialogs::TabModalDialogView> ShowJavaScriptDialog(
    content::WebContents* web_contents,
    const std::u16string& title,
    content::JavaScriptDialogType dialog_type,
    const std::u16string& message_text,
    const std::u16string& default_prompt_text,
    content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
    base::OnceClosure dialog_force_closed_callback) {
  FiberBrowserWindow* window =
      FiberBrowserWindow::FromWebContents(web_contents);
  CHECK(window);
  return FiberJavaScriptDialogView::Show(
      window->GetNativeWindow(), title, dialog_type, message_text,
      default_prompt_text, std::move(dialog_callback),
      std::move(dialog_force_closed_callback));
}

}  // namespace fiber
