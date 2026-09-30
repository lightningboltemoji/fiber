#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <utility>

#import "FiberBridge/FiberPrompt.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/file_system_access/file_system_access_ui_helpers.h"
#include "chrome/grit/generated_resources.h"
#include "components/permissions/permission_uma_constants.h"
#include "components/strings/grit/components_strings.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/dialogs/tab_prompt.h"
#include "fiber/browser/hooks/file_system_access_prompt.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/l10n/l10n_util_mac.h"

namespace fiber {

namespace {

using permissions::PermissionAction;
using RequestData = FileSystemAccessPermissionRequestManager::RequestData;

enum ButtonID {
  kAllowEveryVisit,
  kAllowThisTime,
  kDontAllow,
};

// Chrome's words (see FileSystemAccessRestorePermissionBubbleView).
FiberPromptContent* ContentForPrompt(const RequestData& request,
                                     content::WebContents* web_contents) {
  NSMutableArray<FiberPromptListItem*>* items = [NSMutableArray array];
  for (const auto& file : request.file_request_data) {
    [items addObject:[[FiberPromptListItem alloc]
                         initWithText:base::SysUTF16ToNSString(
                                          file_system_access_ui_helper::
                                              GetPathForDisplayAsParagraph(
                                                  file.path_info))
                               detail:@""]];
  }

  // Allowing waits on a click, and on the prompt having been up a moment, so
  // a page can't rush the user into it.
  return [[FiberPromptContent alloc]
      initWithIcon:nil
           eyebrow:@""
             title:l10n_util::GetNSStringF(
                       IDS_PERMISSIONS_BUBBLE_PROMPT,
                       file_system_access_ui_helper::GetUrlIdentityName(
                           Profile::FromBrowserContext(
                               web_contents->GetBrowserContext()),
                           request.origin.GetURL()))
           message:l10n_util::GetNSString(
                       IDS_FILE_SYSTEM_ACCESS_RESTORE_PERMISSION_DESCRIPTION)
       listHeading:@""
         listItems:items
           buttons:@[
             [[FiberPromptButton alloc]
                 initWithButtonID:kDontAllow
                            title:l10n_util::GetNSString(
                                      IDS_PERMISSION_DONT_ALLOW)
                             role:FiberPromptButtonRoleOther],
             [[FiberPromptButton alloc]
                 initWithButtonID:kAllowThisTime
                            title:l10n_util::GetNSString(
                                      IDS_PERMISSION_ALLOW_THIS_TIME)
                             role:FiberPromptButtonRoleConfirm],
             [[FiberPromptButton alloc]
                 initWithButtonID:kAllowEveryVisit
                            title:l10n_util::GetNSString(
                                      IDS_PERMISSION_ALLOW_EVERY_VISIT)
                             role:FiberPromptButtonRoleConfirm],
           ]];
}

// Owns itself until it answers.
class RestorePrompt {
 public:
  RestorePrompt(const RequestData& request,
                base::OnceCallback<void(PermissionAction)> callback,
                content::WebContents* web_contents)
      : callback_(std::move(callback)) {
    ui_ = TabPrompt::Show(
        web_contents, ContentForPrompt(request, web_contents),
        base::BindOnce(&RestorePrompt::OnEnded, base::Unretained(this)));
  }

 private:
  void OnEnded(std::optional<int> button_id) {
    // Posted: a prompt can end as another takes its place, and answering can
    // show the next.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&RestorePrompt::Answer,
                                  weak_factory_.GetWeakPtr(), button_id));
  }

  // Deletes this. Ending without a button counts as dismissing, as closing
  // Chrome's bubble does.
  void Answer(std::optional<int> button_id) {
    std::unique_ptr<RestorePrompt> self(this);
    PermissionAction action = PermissionAction::DISMISSED;
    if (button_id == kAllowEveryVisit) {
      action = PermissionAction::GRANTED;
    } else if (button_id == kAllowThisTime) {
      action = PermissionAction::GRANTED_ONCE;
    } else if (button_id == kDontAllow) {
      action = PermissionAction::DENIED;
    }
    std::move(callback_).Run(action);
  }

  base::OnceCallback<void(PermissionAction)> callback_;
  std::unique_ptr<TabPrompt> ui_;
  base::WeakPtrFactory<RestorePrompt> weak_factory_{this};
};

}  // namespace

void ShowFileSystemAccessRestorePrompt(
    const RequestData& request,
    base::OnceCallback<void(PermissionAction)> callback,
    content::WebContents* web_contents) {
  new RestorePrompt(request, std::move(callback), web_contents);
}

}  // namespace fiber
