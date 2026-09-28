#include "fiber/browser/extensions/extension_install_dialog.h"

#import <AppKit/AppKit.h>

#include <optional>
#include <utility>

#import "FiberBridge/FiberPrompt.h"
#include "base/functional/bind.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
#include "fiber/browser/dialogs/prompt.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "skia/ext/skia_utils_mac.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/gfx/image/image.h"

namespace fiber {

namespace {

using extensions::InstallPromptData;

enum ButtonID {
  kAccept,
  kCancel,
  kPin,
  kDone,
};

// The Fiber window to ask in: the one the prompt is for, or else the
// profile's last active one (for a prompt from a DevTools window, say, which
// keeps Chrome's UI).
FiberBrowserWindow* WindowForPrompt(
    ExtensionInstallPromptShowParams& show_params) {
  if (content::WebContents* contents = show_params.GetParentWebContents()) {
    if (FiberBrowserWindow* window =
            FiberBrowserWindow::FromWebContents(contents)) {
      return window;
    }
  }
  if (gfx::NativeWindow parent = show_params.GetParentWindow()) {
    if (FiberBrowserWindow* window =
            FiberBrowserWindow::FromNativeWindow(parent)) {
      return window;
    }
  }
  if (!show_params.profile()) {
    return nullptr;
  }
  return FiberBrowserWindow::FromBrowser(
      ProfileBrowserCollection::GetForProfile(show_params.profile())
          ->FindTabbedBrowser());
}

FiberPromptContent* ContentForPrompt(const InstallPromptData& prompt) {
  NSMutableArray<FiberPromptListItem*>* permissions = [NSMutableArray array];
  const extensions::InstallPromptPermissions prompt_permissions =
      prompt.GetPermissions();
  for (size_t i = 0; i < prompt_permissions.permissions.size(); ++i) {
    [permissions
        addObject:[[FiberPromptListItem alloc]
                      initWithText:base::SysUTF16ToNSString(
                                       prompt_permissions.permissions[i])
                            detail:base::SysUTF16ToNSString(
                                       prompt_permissions.details[i])]];
  }

  NSMutableArray<FiberPromptButton*>* buttons = [NSMutableArray array];
  [buttons addObject:[[FiberPromptButton alloc]
                         initWithButtonID:kCancel
                                    title:base::SysUTF16ToNSString(
                                              prompt.GetAbortButtonLabel())
                                     role:FiberPromptButtonRoleCancel]];
  const std::u16string accept_label = prompt.GetAcceptButtonLabel();
  if (!accept_label.empty() &&
      (prompt.GetDialogButtons() &
       static_cast<int>(ui::mojom::DialogButton::kOk))) {
    // As in Chrome's dialog, accepting takes a click, unless the prompt only
    // asks someone else (an administrator, or a parent).
    const bool asks_someone_else =
        prompt.type() == InstallPromptData::EXTENSION_REQUEST_PROMPT ||
        prompt.requires_parent_permission();
    [buttons addObject:[[FiberPromptButton alloc]
                           initWithButtonID:kAccept
                                      title:base::SysUTF16ToNSString(
                                                accept_label)
                                       role:asks_someone_else
                                                ? FiberPromptButtonRoleDefault
                                                : FiberPromptButtonRoleConfirm]];
  }

  return [[FiberPromptContent alloc]
      initWithIcon:prompt.icon().IsEmpty() ? nil : prompt.icon().ToNSImage()
           eyebrow:@""
             title:base::SysUTF16ToNSString(prompt.GetDialogTitle())
           message:@""
       listHeading:permissions.count
                       ? base::SysUTF16ToNSString(
                             prompt.GetPermissionsHeading())
                       : @""
         listItems:permissions
           buttons:buttons];
}

// An install prompt that's up. Owns itself until it ends.
class ExtensionInstallDialog : public extensions::ExtensionRegistryObserver {
 public:
  ExtensionInstallDialog(Profile* profile,
                         ExtensionInstallPrompt::DoneCallback done_callback,
                         std::unique_ptr<InstallPromptData> prompt)
      : done_callback_(std::move(done_callback)), prompt_(std::move(prompt)) {
    if (profile) {
      registry_observation_.Observe(extensions::ExtensionRegistry::Get(profile));
    }
  }

  void Show(FiberBrowserWindow* window) {
    prompt_->OnDialogOpened();
    ui_ = Prompt::Show(window->GetNativeWindow(), ContentForPrompt(*prompt_),
                       base::BindOnce(&ExtensionInstallDialog::OnEnded,
                                      base::Unretained(this)));
  }

 private:
  ~ExtensionInstallDialog() override = default;

  // Deletes this.
  void OnEnded(std::optional<int> button_id) {
    if (button_id == kAccept) {
      prompt_->OnDialogAccepted();
      std::move(done_callback_)
          .Run(ExtensionInstallPrompt::DoneCallbackPayload(
              ExtensionInstallPrompt::Result::ACCEPTED));
    } else {
      prompt_->OnDialogCanceled();
      std::move(done_callback_)
          .Run(ExtensionInstallPrompt::DoneCallbackPayload(
              ExtensionInstallPrompt::Result::USER_CANCELED));
    }
    delete this;
  }

  // extensions::ExtensionRegistryObserver:
  void OnExtensionUninstalled(content::BrowserContext* browser_context,
                              const extensions::Extension* extension,
                              extensions::UninstallReason reason) override {
    // What was asked about is gone.
    if (prompt_->extension() &&
        prompt_->extension()->id() == extension->id()) {
      OnEnded(std::nullopt);
    }
  }

  ExtensionInstallPrompt::DoneCallback done_callback_;
  std::unique_ptr<InstallPromptData> prompt_;
  std::unique_ptr<Prompt> ui_;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
};

}  // namespace

void ShowExtensionInstallDialog(
    std::unique_ptr<ExtensionInstallPromptShowParams> show_params,
    ExtensionInstallPrompt::DoneCallback done_callback,
    std::unique_ptr<InstallPromptData> prompt) {
  FiberBrowserWindow* window = WindowForPrompt(*show_params);
  if (!window) {
    std::move(done_callback)
        .Run(ExtensionInstallPrompt::DoneCallbackPayload(
            ExtensionInstallPrompt::Result::ABORTED));
    return;
  }
  // Like Chrome's dialog, the tab it's for comes forward.
  window->ActivateTab(show_params->GetParentWebContents());
  (new ExtensionInstallDialog(show_params->profile(), std::move(done_callback),
                              std::move(prompt)))
      ->Show(window);
}

void ShowExtensionInstalled(
    BrowserWindowInterface* browser,
    scoped_refptr<const extensions::Extension> extension,
    const SkBitmap* icon) {
  FiberBrowserWindow* window = FiberBrowserWindow::FromBrowser(browser);
  if (!window) {
    return;
  }
  Profile* profile = browser->GetProfile();
  NSMutableArray<FiberPromptButton*>* buttons = [NSMutableArray array];
  if (!profile->IsOffTheRecord()) {
    [buttons addObject:[[FiberPromptButton alloc]
                           initWithButtonID:kPin
                                      title:@"Pin to Toolbar"
                                       role:FiberPromptButtonRoleOther]];
  }
  [buttons addObject:[[FiberPromptButton alloc]
                         initWithButtonID:kDone
                                    title:@"Done"
                                     role:FiberPromptButtonRoleDefault]];
  FiberPromptContent* content = [[FiberPromptContent alloc]
      initWithIcon:icon && !icon->isNull() ? skia::SkBitmapToNSImage(*icon)
                                           : nil
           eyebrow:@""
             title:[NSString stringWithFormat:@"Added “%@”",
                                              base::SysUTF8ToNSString(
                                                  extension->name())]
           message:@"Open it from the extensions menu, at the end of the "
                   @"toolbar."
       listHeading:@""
         listItems:@[]
           buttons:buttons];

  // Owns the prompt until it ends.
  auto holder = std::make_unique<std::unique_ptr<Prompt>>();
  std::unique_ptr<Prompt>* prompt = holder.get();
  *prompt = Prompt::Show(
      window->GetNativeWindow(), content,
      base::BindOnce(
          [](std::unique_ptr<std::unique_ptr<Prompt>> holder,
             base::WeakPtr<Profile> profile, extensions::ExtensionId id,
             std::optional<int> button_id) {
            if (button_id != kPin || !profile) {
              return;
            }
            ToolbarActionsModel* model = ToolbarActionsModel::Get(profile.get());
            if (model && model->HasAction(id) && !model->IsActionPinned(id) &&
                !model->IsActionForcePinned(id)) {
              model->SetActionVisibility(id, true);
            }
          },
          std::move(holder), profile->GetWeakPtr(), extension->id()));
}

}  // namespace fiber
