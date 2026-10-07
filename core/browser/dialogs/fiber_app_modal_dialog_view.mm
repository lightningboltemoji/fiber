#include "fiber/browser/dialogs/fiber_app_modal_dialog_view.h"

#import <Cocoa/Cocoa.h>

#include <utility>

#import "FiberBridge/FiberJavaScriptDialog.h"
#import "FiberBridge/FiberPrompt.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/notreached.h"
#include "base/strings/sys_string_conversions.h"
#import "chrome/browser/chrome_browser_application_mac.h"
#include "chrome/browser/ui/blocked_content/popunder_preventer.h"
#include "components/javascript_dialogs/app_modal_dialog_controller.h"
#include "components/strings/grit/components_strings.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "fiber/browser/dialogs/prompt.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/strings/grit/ui_strings.h"

// Forwards how the dialog ended to its FiberAppModalDialogView.
@interface FiberAppModalDialogViewActions
    : NSObject <FiberJavaScriptDialogActions>
- (instancetype)initWithOwner:(fiber::FiberAppModalDialogView*)owner;
- (void)detachOwner;
@end

@implementation FiberAppModalDialogViewActions {
  raw_ptr<fiber::FiberAppModalDialogView> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberAppModalDialogView*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)dialogDidAcceptWithInput:(NSString*)input {
  if (_owner) {
    _owner->OnAccepted(base::SysNSStringToUTF16(input));
  }
}

- (void)dialogDidCancel {
  if (_owner) {
    _owner->OnCancelled();
  }
}

- (void)dialogDidDismiss {
  if (_owner) {
    _owner->OnDismissed();
  }
}

@end

namespace fiber {

namespace {

enum LeaveButtonID {
  kLeave,
  kStay,
};

FiberJavaScriptDialogKind DialogKind(content::JavaScriptDialogType type) {
  switch (type) {
    case content::JAVASCRIPT_DIALOG_TYPE_ALERT:
      return FiberJavaScriptDialogKindAlert;
    case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
      return FiberJavaScriptDialogKindConfirm;
    case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
      return FiberJavaScriptDialogKindPrompt;
  }
  NOTREACHED();
}

// The site the user knows the page by, "en.wikipedia.org".
NSString* SiteForDisplay(content::WebContents* web_contents) {
  return base::SysUTF16ToNSString(url_formatter::FormatOriginForSecurityDisplay(
      web_contents->GetPrimaryMainFrame()->GetLastCommittedOrigin(),
      url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS));
}

// Chrome's words for leaving or reloading the page, under its site.
FiberPromptContent* LeavePromptContent(
    const javascript_dialogs::AppModalDialogController& controller) {
  return [[FiberPromptContent alloc]
      initWithIcon:nil
             topic:FiberPromptTopicLeave
           eyebrow:SiteForDisplay(controller.web_contents())
             title:base::SysUTF16ToNSString(controller.title())
           message:base::SysUTF16ToNSString(controller.message_text())
       listHeading:@""
         listItems:@[]
           buttons:@[
             [[FiberPromptButton alloc]
                 initWithButtonID:kStay
                            title:l10n_util::GetNSString(IDS_APP_CANCEL)
                             role:FiberPromptButtonRoleCancel],
             [[FiberPromptButton alloc]
                 initWithButtonID:kLeave
                            title:
                                l10n_util::GetNSString(
                                    controller.is_reload()
                                        ? IDS_BEFORERELOAD_MESSAGEBOX_OK_BUTTON_LABEL
                                        : IDS_BEFOREUNLOAD_MESSAGEBOX_OK_BUTTON_LABEL)
                             role:FiberPromptButtonRoleDefault],
           ]];
}

}  // namespace

// static
javascript_dialogs::AppModalDialogView* FiberAppModalDialogView::Create(
    std::unique_ptr<javascript_dialogs::AppModalDialogController> controller) {
  content::WebContents* web_contents = controller->web_contents();
  auto* view = new FiberAppModalDialogView(std::move(controller));
  // Like Chrome's, the page's tab comes forward as the dialog is made.
  if (web_contents->GetDelegate()) {
    web_contents->GetDelegate()->ActivateContents(web_contents);
  }
  return view;
}

FiberAppModalDialogView::FiberAppModalDialogView(
    std::unique_ptr<javascript_dialogs::AppModalDialogController> controller)
    : controller_(std::move(controller)),
      popunder_preventer_(
          std::make_unique<PopunderPreventer>(controller_->web_contents())),
      actions_([[FiberAppModalDialogViewActions alloc] initWithOwner:this]) {}

FiberAppModalDialogView::~FiberAppModalDialogView() {
  CloseDialog();
}

void FiberAppModalDialogView::OnAccepted(const std::u16string& input) {
  controller_->OnAccept(input, /*suppress_js_messages=*/false);
  delete this;
}

void FiberAppModalDialogView::OnCancelled() {
  // Staying on the page stops a quit that asked it.
  if (controller_->is_before_unload_dialog()) {
    chrome_browser_application_mac::CancelTerminate();
  }
  controller_->OnCancel(/*suppress_js_messages=*/false);
  delete this;
}

void FiberAppModalDialogView::OnDismissed() {
  controller_->OnClose();
  delete this;
}

void FiberAppModalDialogView::ShowAppModalDialog() {
  content::WebContents* web_contents = controller_->web_contents();
  FiberBrowserWindow* window =
      FiberBrowserWindow::FromWebContents(web_contents);
  if (!window) {
    // There's nowhere to ask, so the answer is no.
    OnCancelled();
    return;
  }

  if (controller_->is_before_unload_dialog()) {
    leave_prompt_ = Prompt::ShowForTab(
        web_contents, LeavePromptContent(*controller_),
        base::BindOnce(&FiberAppModalDialogView::OnLeavePromptEnded,
                       base::Unretained(this)));
    return;
  }
  FiberJavaScriptDialogContent* content = [[FiberJavaScriptDialogContent alloc]
           initWithKind:DialogKind(controller_->javascript_dialog_type())
                  title:base::SysUTF16ToNSString(controller_->title())
                message:base::SysUTF16ToNSString(controller_->message_text())
      defaultPromptText:base::SysUTF16ToNSString(
                            controller_->default_prompt_text())
      acceptButtonTitle:l10n_util::GetNSString(IDS_APP_OK)
      cancelButtonTitle:l10n_util::GetNSString(IDS_APP_CANCEL)];
  dialog_ = [FiberJavaScriptDialogFactory
      dialogWithContent:content
                 window:window->GetNativeWindow().GetNativeNSWindow()
                actions:actions_];
}

void FiberAppModalDialogView::OnLeavePromptEnded(std::optional<int> button_id) {
  // Ending without an answer (another prompt took its place, say) stays.
  if (button_id == kLeave) {
    OnAccepted(std::u16string());
  } else {
    OnCancelled();
  }
}

void FiberAppModalDialogView::ActivateAppModalDialog() {
  content::WebContents* web_contents = controller_->web_contents();
  if (web_contents->GetDelegate()) {
    web_contents->GetDelegate()->ActivateContents(web_contents);
  }
}

void FiberAppModalDialogView::CloseAppModalDialog() {
  CloseDialog();
  OnDismissed();
}

void FiberAppModalDialogView::AcceptAppModalDialog() {
  std::u16string input = dialog_ ? base::SysNSStringToUTF16(dialog_.userInput)
                                 : controller_->default_prompt_text();
  CloseDialog();
  OnAccepted(input);
}

void FiberAppModalDialogView::CancelAppModalDialog() {
  CloseDialog();
  OnCancelled();
}

bool FiberAppModalDialogView::IsShowing() const {
  return dialog_ != nil || leave_prompt_;
}

void FiberAppModalDialogView::CloseDialog() {
  leave_prompt_.reset();
  // Closing reports -dialogDidDismiss, which would delete this.
  [actions_ detachOwner];
  id<FiberJavaScriptDialog> dialog = dialog_;
  dialog_ = nil;
  [dialog close];
}

}  // namespace fiber
