#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#import "FiberBridge/FiberPrompt.h"
#include "base/functional/bind.h"
#include "base/strings/strcat.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/login/login_handler.h"
#include "components/strings/grit/components_strings.h"
#include "fiber/browser/dialogs/tab_prompt.h"
#include "fiber/browser/hooks/page_dialogs.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/strings/grit/ui_strings.h"

namespace fiber {

namespace {

enum ButtonID {
  kSignIn,
  kCancel,
};

// Chrome's words (see LoginView).
FiberPromptContent* ContentForPrompt(const std::u16string& authority,
                                     const std::u16string& explanation) {
  const std::u16string message =
      explanation.empty() ? authority
                          : base::StrCat({authority, u"\n", explanation});
  return [[FiberPromptContent alloc]
       initWithIcon:nil
              topic:FiberPromptTopicSignIn
            eyebrow:@""
              title:l10n_util::GetNSString(IDS_LOGIN_DIALOG_TITLE)
            message:base::SysUTF16ToNSString(message)
        listHeading:@""
          listItems:@[]
             fields:@[
               [[FiberPromptField alloc]
                   initWithPlaceholder:l10n_util::GetNSString(
                                           IDS_LOGIN_DIALOG_USERNAME_FIELD)
                                  text:@""
                                  kind:FiberPromptFieldKindUsername],
               [[FiberPromptField alloc]
                   initWithPlaceholder:l10n_util::GetNSString(
                                           IDS_LOGIN_DIALOG_PASSWORD_FIELD)
                                  text:@""
                                  kind:FiberPromptFieldKindPassword],
             ]
      checkboxTitle:@""
            buttons:@[
              [[FiberPromptButton alloc]
                  initWithButtonID:kCancel
                             title:l10n_util::GetNSString(IDS_APP_CANCEL)
                              role:FiberPromptButtonRoleCancel],
              [[FiberPromptButton alloc]
                  initWithButtonID:kSignIn
                             title:l10n_util::GetNSString(
                                       IDS_LOGIN_DIALOG_OK_BUTTON_LABEL)
                              role:FiberPromptButtonRoleDefault],
            ]];
}

class FiberLoginHandler : public LoginHandler {
 public:
  FiberLoginHandler(
      const net::AuthChallengeInfo& auth_info,
      content::WebContents* web_contents,
      content::LoginDelegate::LoginAuthRequiredCallback auth_required_callback)
      : LoginHandler(auth_info,
                     web_contents,
                     std::move(auth_required_callback)) {}

  // LoginHandler can't call CloseDialog() as it goes: this is gone by then.
  ~FiberLoginHandler() override { ui_.reset(); }

 protected:
  // LoginHandler:
  bool BuildViewImpl(const std::u16string& authority,
                     const std::u16string& explanation,
                     LoginModelData* login_model_data) override {
    if (!web_contents() || !FiberBrowserWindow::FromWebContents(web_contents())) {
      return false;
    }
    ui_ = TabPrompt::Show(web_contents(),
                          ContentForPrompt(authority, explanation),
                          base::BindOnce(&FiberLoginHandler::OnEnded,
                                         base::Unretained(this)));
    return true;
  }

  void CloseDialog() override { ui_.reset(); }

 private:
  // Can destroy this.
  void OnEnded(std::optional<int> button_id) {
    if (button_id != kSignIn) {
      CancelAuth(/*notify_others=*/true);
      return;
    }
    const std::vector<std::u16string> values = ui_->prompt().GetFieldValues();
    SetAuth(values[0], values[1]);
  }

  std::unique_ptr<TabPrompt> ui_;
};

}  // namespace

std::unique_ptr<LoginHandler> CreateLoginHandler(
    const net::AuthChallengeInfo& auth_info,
    content::WebContents* web_contents,
    content::LoginDelegate::LoginAuthRequiredCallback auth_required_callback) {
  return std::make_unique<FiberLoginHandler>(auth_info, web_contents,
                                             std::move(auth_required_callback));
}

}  // namespace fiber
