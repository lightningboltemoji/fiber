#ifndef FIBER_BROWSER_DIALOGS_FIBER_PERMISSION_PROMPT_H_
#define FIBER_BROWSER_DIALOGS_FIBER_PERMISSION_PROMPT_H_

#include <memory>

#include "components/permissions/permission_prompt.h"

namespace content {
class WebContents;
}

namespace fiber {

// Asks whether the tab `web_contents`, in a Fiber window, may do what
// `delegate`'s requests are for, over its veiled page, in Chrome's words and
// with its choices. Destroying the prompt takes it down without an answer.
std::unique_ptr<permissions::PermissionPrompt> ShowPermissionPrompt(
    content::WebContents* web_contents,
    permissions::PermissionPrompt::Delegate* delegate);

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_FIBER_PERMISSION_PROMPT_H_
