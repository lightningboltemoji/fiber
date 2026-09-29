#ifndef FIBER_BROWSER_HOOKS_JAVASCRIPT_DIALOG_FACTORY_H_
#define FIBER_BROWSER_HOOKS_JAVASCRIPT_DIALOG_FACTORY_H_

#include <string>

#include "base/functional/callback_forward.h"
#include "base/memory/weak_ptr.h"
#include "components/javascript_dialogs/tab_modal_dialog_view.h"
#include "content/public/browser/javascript_dialog_manager.h"

namespace content {
class WebContents;
}

namespace fiber {

// Shows a JavaScript alert, confirm, prompt, or beforeunload dialog for the tab
// `web_contents` as a sheet on its Fiber window. See
// javascript_dialogs::TabModalDialogManagerDelegate::CreateNewDialog().
base::WeakPtr<javascript_dialogs::TabModalDialogView> ShowJavaScriptDialog(
    content::WebContents* web_contents,
    const std::u16string& title,
    content::JavaScriptDialogType dialog_type,
    const std::u16string& message_text,
    const std::u16string& default_prompt_text,
    content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
    base::OnceClosure dialog_force_closed_callback);

// Makes Fiber's UI show the JavaScript dialogs Chrome shows app-modally, every
// page's beforeunload prompt among them. Called at startup (see
// patches/chromium/chrome-browser-chrome_browser_main.cc.patch).
void InstallAppModalDialogFactory();

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_JAVASCRIPT_DIALOG_FACTORY_H_
