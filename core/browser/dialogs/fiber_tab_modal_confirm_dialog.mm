#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <utility>

#import "FiberBridge/FiberPrompt.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/tab_modal_confirm_dialog.h"
#include "chrome/browser/ui/tab_modal_confirm_dialog_delegate.h"
#include "fiber/browser/dialogs/tab_prompt.h"
#include "fiber/browser/hooks/page_dialogs.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/gfx/image/image.h"

namespace fiber {

namespace {

using ui::mojom::DialogButton;

FiberPromptContent* ContentForDialog(TabModalConfirmDialogDelegate& delegate) {
  const int dialog_buttons = delegate.GetDialogButtons();
  // Without the delegate's say, OK is the default, as in Chrome's dialog.
  const int default_button = delegate.GetDefaultDialogButton().value_or(
      static_cast<int>(DialogButton::kOk));
  NSMutableArray<FiberPromptButton*>* buttons = [NSMutableArray array];
  if (dialog_buttons & static_cast<int>(DialogButton::kCancel)) {
    [buttons addObject:[[FiberPromptButton alloc]
                           initWithButtonID:static_cast<int>(
                                                DialogButton::kCancel)
                                      title:base::SysUTF16ToNSString(
                                                delegate.GetCancelButtonTitle())
                                       role:FiberPromptButtonRoleCancel]];
  }
  if (dialog_buttons & static_cast<int>(DialogButton::kOk)) {
    [buttons addObject:[[FiberPromptButton alloc]
                           initWithButtonID:static_cast<int>(DialogButton::kOk)
                                      title:base::SysUTF16ToNSString(
                                                delegate.GetAcceptButtonTitle())
                                       role:default_button ==
                                                    static_cast<int>(
                                                        DialogButton::kOk)
                                                ? FiberPromptButtonRoleDefault
                                                : FiberPromptButtonRoleOther]];
  }
  gfx::Image* icon = delegate.GetIcon();
  return [[FiberPromptContent alloc]
      initWithIcon:icon && !icon->IsEmpty() ? icon->ToNSImage() : nil
             topic:FiberPromptTopicGeneral
           eyebrow:@""
             title:base::SysUTF16ToNSString(delegate.GetTitle())
           message:base::SysUTF16ToNSString(delegate.GetDialogMessage())
       listHeading:@""
         listItems:@[]
           buttons:buttons];
}

// Owns itself and its delegate until the delegate closes it.
class FiberTabModalConfirmDialog : public TabModalConfirmDialog {
 public:
  FiberTabModalConfirmDialog(
      std::unique_ptr<TabModalConfirmDialogDelegate> delegate,
      content::WebContents* web_contents)
      : delegate_(std::move(delegate)) {
    delegate_->set_close_delegate(this);
    ui_ = TabPrompt::Show(
        web_contents, ContentForDialog(*delegate_),
        base::BindOnce(&FiberTabModalConfirmDialog::OnEnded,
                       base::Unretained(this)));
  }

  // TabModalConfirmDialog:
  void AcceptTabModalDialog() override { delegate_->Accept(); }
  void CancelTabModalDialog() override { delegate_->Cancel(); }
  void CloseDialog() override {
    ui_.reset();
    if (closing_) {
      return;
    }
    closing_ = true;
    // Soon: the delegate closes this from within its own calls.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([](FiberTabModalConfirmDialog* dialog) {
                     delete dialog;
                   },
                                  base::Unretained(this)));
  }

 private:
  ~FiberTabModalConfirmDialog() override = default;

  void OnEnded(std::optional<int> button_id) {
    if (button_id == static_cast<int>(DialogButton::kOk)) {
      delegate_->Accept();
    } else if (button_id == static_cast<int>(DialogButton::kCancel)) {
      delegate_->Cancel();
    } else {
      delegate_->Close();
    }
  }

  std::unique_ptr<TabModalConfirmDialogDelegate> delegate_;
  std::unique_ptr<TabPrompt> ui_;
  bool closing_ = false;
};

}  // namespace

TabModalConfirmDialog* CreateTabModalConfirmDialog(
    std::unique_ptr<TabModalConfirmDialogDelegate> delegate,
    content::WebContents* web_contents) {
  return new FiberTabModalConfirmDialog(std::move(delegate), web_contents);
}

}  // namespace fiber
