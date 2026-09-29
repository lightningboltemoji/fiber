#ifndef FIBER_BROWSER_HOOKS_PERMISSION_PROMPT_H_
#define FIBER_BROWSER_HOOKS_PERMISSION_PROMPT_H_

#include <memory>

#include "components/permissions/permission_prompt.h"

namespace content {
class WebContents;
}

namespace fiber {

// For CreatePermissionPrompt() in a Fiber window: Fiber's prompt, or, for
// requests Chrome would show where Fiber has nothing to (its location bar's
// quiet chip, say), none, and the request is ignored.
std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* web_contents,
    permissions::PermissionPrompt::Delegate* delegate);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_PERMISSION_PROMPT_H_
