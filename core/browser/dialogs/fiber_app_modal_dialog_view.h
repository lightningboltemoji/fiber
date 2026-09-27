#ifndef FIBER_BROWSER_DIALOGS_FIBER_APP_MODAL_DIALOG_VIEW_H_
#define FIBER_BROWSER_DIALOGS_FIBER_APP_MODAL_DIALOG_VIEW_H_

#include <memory>
#include <string>

#include "components/javascript_dialogs/app_modal_dialog_view.h"

@class FiberAppModalDialogViewActions;
@protocol FiberJavaScriptDialog;
class PopunderPreventer;

namespace javascript_dialogs {
class AppModalDialogController;
}

namespace fiber {

// A JavaScript dialog Chrome shows app-modally, in Fiber's UI. Mostly that's a
// page asking before it's left or reloaded (beforeunload), which Fiber asks
// over the page, veiled; otherwise it's an alert, confirm, or prompt from a
// page without a tab-modal dialog manager, shown as a sheet like a tab's.
// Dialogs for pages outside Fiber's windows are cancelled. Owns itself, and
// its controller, until the dialog ends.
class FiberAppModalDialogView : public javascript_dialogs::AppModalDialogView {
 public:
  FiberAppModalDialogView(const FiberAppModalDialogView&) = delete;
  FiberAppModalDialogView& operator=(const FiberAppModalDialogView&) = delete;

  // javascript_dialogs::AppModalDialogManager's native dialog factory (see
  // fiber::InstallAppModalDialogFactory()).
  static javascript_dialogs::AppModalDialogView* Create(
      std::unique_ptr<javascript_dialogs::AppModalDialogController>
          controller);

  // Called by the dialog's actions when it ends. Each deletes this.
  void OnAccepted(const std::u16string& input);
  void OnCancelled();
  void OnDismissed();

  // javascript_dialogs::AppModalDialogView:
  void ShowAppModalDialog() override;
  void ActivateAppModalDialog() override;
  void CloseAppModalDialog() override;
  void AcceptAppModalDialog() override;
  void CancelAppModalDialog() override;
  bool IsShowing() const override;

 private:
  explicit FiberAppModalDialogView(
      std::unique_ptr<javascript_dialogs::AppModalDialogController>
          controller);
  ~FiberAppModalDialogView() override;

  // Takes the dialog down without reporting how it ended.
  void CloseDialog();

  std::unique_ptr<javascript_dialogs::AppModalDialogController> controller_;
  std::unique_ptr<PopunderPreventer> popunder_preventer_;
  FiberAppModalDialogViewActions* __strong actions_;
  id<FiberJavaScriptDialog> __strong dialog_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_FIBER_APP_MODAL_DIALOG_VIEW_H_
