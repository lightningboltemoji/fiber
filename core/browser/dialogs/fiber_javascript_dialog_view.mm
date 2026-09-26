#include "fiber/browser/dialogs/fiber_javascript_dialog_view.h"

#import <Cocoa/Cocoa.h>

#include <utility>

#import "FiberBridge/FiberJavaScriptDialog.h"
#include "base/memory/raw_ptr.h"
#include "base/notreached.h"
#include "base/strings/sys_string_conversions.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/strings/grit/ui_strings.h"

// Forwards how the dialog ended to its FiberJavaScriptDialogView.
@interface FiberJavaScriptDialogViewActions
    : NSObject <FiberJavaScriptDialogActions>
- (instancetype)initWithOwner:(fiber::FiberJavaScriptDialogView*)owner;
- (void)detachOwner;
@end

@implementation FiberJavaScriptDialogViewActions {
  raw_ptr<fiber::FiberJavaScriptDialogView> _owner;
}

- (instancetype)initWithOwner:(fiber::FiberJavaScriptDialogView*)owner {
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

}  // namespace

// static
base::WeakPtr<FiberJavaScriptDialogView> FiberJavaScriptDialogView::Show(
    gfx::NativeWindow window,
    const std::u16string& title,
    content::JavaScriptDialogType dialog_type,
    const std::u16string& message_text,
    const std::u16string& default_prompt_text,
    content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
    base::OnceClosure dialog_force_closed_callback) {
  // Deletes itself once the dialog's actions report that it ended.
  auto* view = new FiberJavaScriptDialogView(
      std::move(dialog_callback), std::move(dialog_force_closed_callback));
  FiberJavaScriptDialogContent* content = [[FiberJavaScriptDialogContent alloc]
           initWithKind:DialogKind(dialog_type)
                  title:base::SysUTF16ToNSString(title)
                message:base::SysUTF16ToNSString(message_text)
      defaultPromptText:base::SysUTF16ToNSString(default_prompt_text)
      acceptButtonTitle:l10n_util::GetNSString(IDS_APP_OK)
      cancelButtonTitle:l10n_util::GetNSString(IDS_APP_CANCEL)];
  view->dialog_ =
      [FiberJavaScriptDialogFactory dialogWithContent:content
                                               window:window.GetNativeNSWindow()
                                              actions:view->actions_];
  return view->weak_factory_.GetWeakPtr();
}

FiberJavaScriptDialogView::FiberJavaScriptDialogView(
    content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
    base::OnceClosure dialog_force_closed_callback)
    : dialog_callback_(std::move(dialog_callback)),
      dialog_force_closed_callback_(std::move(dialog_force_closed_callback)),
      actions_([[FiberJavaScriptDialogViewActions alloc] initWithOwner:this]) {}

FiberJavaScriptDialogView::~FiberJavaScriptDialogView() {
  [actions_ detachOwner];
}

void FiberJavaScriptDialogView::OnAccepted(const std::u16string& input) {
  if (dialog_callback_) {
    std::move(dialog_callback_).Run(/*success=*/true, input);
  }
  delete this;
}

void FiberJavaScriptDialogView::OnCancelled() {
  if (dialog_callback_) {
    std::move(dialog_callback_).Run(/*success=*/false, std::u16string());
  }
  delete this;
}

void FiberJavaScriptDialogView::OnDismissed() {
  if (dialog_force_closed_callback_) {
    std::move(dialog_force_closed_callback_).Run();
  }
  delete this;
}

void FiberJavaScriptDialogView::CloseDialogWithoutCallback() {
  dialog_callback_.Reset();
  dialog_force_closed_callback_.Reset();
  // Ending the dialog reports OnDismissed(), which may delete this before
  // -close returns.
  id<FiberJavaScriptDialog> dialog = dialog_;
  [dialog close];
}

std::u16string FiberJavaScriptDialogView::GetUserInput() {
  return base::SysNSStringToUTF16(dialog_.userInput);
}

}  // namespace fiber
