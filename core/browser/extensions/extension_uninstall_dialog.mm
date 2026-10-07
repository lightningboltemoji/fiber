#include "fiber/browser/extensions/extension_uninstall_dialog.h"

#import <AppKit/AppKit.h>

#include <optional>

#import "FiberBridge/FiberPrompt.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/grit/generated_resources.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/extension.h"
#include "fiber/browser/dialogs/prompt.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/gfx/image/image_skia_util_mac.h"
#include "ui/strings/grit/ui_strings.h"

namespace fiber {

namespace {

using extensions::ExtensionUninstallDialog;

enum ButtonID {
  kRemove,
  kCancel,
};

class FiberExtensionUninstallDialog : public ExtensionUninstallDialog {
 public:
  FiberExtensionUninstallDialog(Profile* profile,
                                gfx::NativeWindow parent,
                                Delegate* delegate)
      : ExtensionUninstallDialog(profile, parent, delegate),
        profile_(profile->GetWeakPtr()) {}

 private:
  // ExtensionUninstallDialog:
  void Show() override {
    FiberBrowserWindow* window = FiberBrowserWindow::FromNativeWindow(parent());
    if (!window && profile_) {
      window = FiberBrowserWindow::FromBrowser(
          ProfileBrowserCollection::GetForProfile(profile_.get())
              ->FindTabbedBrowser());
    }
    if (!window) {
      Close();
      return;
    }

    NSString* message = @"";
    if (triggering_extension()) {
      message = l10n_util::GetNSStringF(
          IDS_EXTENSION_PROMPT_UNINSTALL_TRIGGERED_BY_EXTENSION,
          extensions::ui_util::GetFixupExtensionNameForUIDisplay(
              triggering_extension()->name()));
    }
    FiberPromptContent* content = [[FiberPromptContent alloc]
        initWithIcon:icon().isNull() ? nil : gfx::NSImageFromImageSkia(icon())
               topic:FiberPromptTopicExtension
             eyebrow:@""
               title:l10n_util::GetNSStringF(
                         IDS_EXTENSION_PROMPT_UNINSTALL_TITLE,
                         extensions::ui_util::
                             GetFixupExtensionNameForUIDisplay(
                                 extension()->name()))
             message:message
         listHeading:@""
           listItems:@[]
             buttons:@[
               [[FiberPromptButton alloc]
                   initWithButtonID:kCancel
                              title:l10n_util::GetNSString(IDS_APP_CANCEL)
                               role:FiberPromptButtonRoleCancel],
               [[FiberPromptButton alloc]
                   initWithButtonID:kRemove
                              title:l10n_util::GetNSString(
                                        IDS_EXTENSION_PROMPT_UNINSTALL_BUTTON)
                               role:FiberPromptButtonRoleDefault],
             ]];
    ui_ = Prompt::Show(
        window->GetNativeWindow(), content,
        base::BindOnce(&FiberExtensionUninstallDialog::OnEnded,
                       base::Unretained(this)));
  }

  void Close() override {
    ui_.reset();
    // Soon, as Chrome's dialog closes; not from within whatever closed it.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<ExtensionUninstallDialog> dialog) {
                         if (dialog) {
                           dialog->OnDialogClosed(CLOSE_ACTION_CANCELED);
                         }
                       },
                       AsWeakPtr()));
  }

  // May delete this.
  void OnEnded(std::optional<int> button_id) {
    OnDialogClosed(button_id == kRemove ? CLOSE_ACTION_UNINSTALL
                                        : CLOSE_ACTION_CANCELED);
  }

  const base::WeakPtr<Profile> profile_;
  std::unique_ptr<Prompt> ui_;
};

}  // namespace

std::unique_ptr<ExtensionUninstallDialog> CreateUninstallDialog(
    Profile* profile,
    gfx::NativeWindow parent,
    ExtensionUninstallDialog::Delegate* delegate) {
  return std::make_unique<FiberExtensionUninstallDialog>(profile, parent,
                                                         delegate);
}

}  // namespace fiber
