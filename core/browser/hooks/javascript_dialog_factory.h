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

// Whether `web_contents` is a tab in a Fiber window. Called from Chrome's
// JavaScript dialog factory (see patches/chromium/
// chrome-browser-ui-views-javascript_tab_modal_dialog_view_views.cc.patch),
// since Chrome's views dialogs need a views window to attach to.
bool IsInFiberWindow(content::WebContents* web_contents);

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

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_JAVASCRIPT_DIALOG_FACTORY_H_
