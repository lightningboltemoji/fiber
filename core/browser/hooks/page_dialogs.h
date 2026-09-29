#ifndef FIBER_BROWSER_HOOKS_PAGE_DIALOGS_H_
#define FIBER_BROWSER_HOOKS_PAGE_DIALOGS_H_

#include <memory>
#include <optional>
#include <string>

#include "content/public/browser/login_delegate.h"
#include "content/public/browser/weak_document_ptr.h"

class GURL;
class LoginHandler;
class TabModalConfirmDialog;
class TabModalConfirmDialogDelegate;

namespace content {
class WebContents;
}

namespace net {
class AuthChallengeInfo;
}

namespace url {
class Origin;
}

// Fiber's prompts, over the veiled page, in place of the dialogs Chrome shows
// over a tab in a Fiber window, which has no views window for them. Each is
// called from Chrome's factory for its dialog.
namespace fiber {

// For TabModalConfirmDialog::Create(): confirming a form's resubmission, say.
// Owns itself until `delegate` closes it.
TabModalConfirmDialog* CreateTabModalConfirmDialog(
    std::unique_ptr<TabModalConfirmDialogDelegate> delegate,
    content::WebContents* web_contents);

// For ExternalProtocolHandler::RunExternalProtocolDialog(): whether to open
// `url` in `program_name`, another app.
void ShowExternalProtocolDialog(
    const GURL& url,
    content::WebContents* web_contents,
    const std::optional<url::Origin>& initiating_origin,
    content::WeakDocumentPtr initiator_document,
    const std::u16string& program_name);

// For LoginHandler::Create(): a site's or proxy's request for a username and
// password.
std::unique_ptr<LoginHandler> CreateLoginHandler(
    const net::AuthChallengeInfo& auth_info,
    content::WebContents* web_contents,
    content::LoginDelegate::LoginAuthRequiredCallback auth_required_callback);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_PAGE_DIALOGS_H_
