#ifndef FIBER_BROWSER_HOOKS_FILE_SYSTEM_ACCESS_PROMPT_H_
#define FIBER_BROWSER_HOOKS_FILE_SYSTEM_ACCESS_PROMPT_H_

#include "base/functional/callback.h"
#include "chrome/browser/file_system_access/file_system_access_permission_request_manager.h"

namespace content {
class WebContents;
}

namespace permissions {
enum class PermissionAction;
}

namespace fiber {

// For ShowFileSystemAccessRestorePermissionDialog() in a Fiber window: Fiber's
// prompt, over the page, in place of Chrome's bubble on its location bar,
// asking whether a site gets back the files it had on an earlier visit.
void ShowFileSystemAccessRestorePrompt(
    const FileSystemAccessPermissionRequestManager::RequestData& request,
    base::OnceCallback<void(permissions::PermissionAction)> callback,
    content::WebContents* web_contents);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_FILE_SYSTEM_ACCESS_PROMPT_H_
